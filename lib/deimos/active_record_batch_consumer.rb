# frozen_string_literal: true

require 'deimos/active_record_base_consumer'
require 'deimos/batch_consumer'
require 'deimos/schema_model_converter'
require 'activerecord-import'

module Deimos
  # Consumer that automatically saves batches of payloads into the database.
  class ActiveRecordBatchConsumer < BatchConsumer
    include ActiveRecordBaseConsumer

    # Create new consumer
    def initialize
      init_consumer

      super
    end

    # Handle a batch of Kafka messages
    # @param payloads [Array<Hash>] Decoded payloads.
    # @param metadata [Hash] Information about batch, including keys.
    def consume_batch(payloads, metadata)
      # Create [key, value] pairs, even if no keys are decoded
      messages = payloads.
        zip(metadata[:keys]).
        map { |p, k| [k, p] }

      Deimos.instrument('ar_consumer.consume_batch', topic: metadata[:topic], messages: messages) do
        slices = _slice_batch(messages)

        # The entire batch should be treated as one transaction so that if
        # any message fails, the whole thing is rolled back
        ActiveRecord::Base.transaction do
          slices.each do |slice|
            removed, upserted = slice.partition { |_, v| v.nil? }

            upsert_records(upserted) unless upserted.empty?
            remove_records(removed) unless removed.empty?
          end
        end
      end
    end

  protected

    # Upsert any non-deleted records
    # @param records [Array<Array>] List of [key, value] pairs for a group of
    # non-tombstone records.
    def upsert_records(records)
      key_cols = key_columns(records)

      messages = records.map { |k, v| record_attributes(k, v) }

      # If record_attributes indicated no record, skip it
      messages.compact!

      options = if key_cols.empty?
                  {} # Can't upsert with no key, just do regular insert
                else
                  {
                    on_duplicate_key_update: {
                      # conflict_target must explicitly list the columns for
                      # Postgres and SQLite
                      conflict_target: key_cols,
                      columns: :all
                    }
                  }
                end

      @klass.import!(messages, options)
    end

    # Delete any records with a tombstone.
    # @param records [Array<Array>] List of [key, nil] pairs for a group of
    # deleted records.
    def remove_records(records)
      clause = deleted_query(records)

      clause.delete_all
    end

    # Get unique key for the ActiveRecord instance from the incoming key.
    # Override this method (with super) to customize the set of attributes that
    # uniquely identifies each record in the database.
    # @param key [Hash] The decoded key.
    # @return [Hash] The key attributes.
    def record_key(key)
      decoded_key = decode_key(key)

      if decoded_key.nil?
        {}
      elsif decoded_key.is_a?(Hash)
        @key_converter.convert(decoded_key)
      else
        { @klass.primary_key => decoded_key }
      end
    end

    # Get attributes for new/upserted records in the database. Override this
    # method (with super) to customize the set of attributes used to instantiate
    # records.
    # @param payload [Hash] The decoded message payload.
    # @param key [Hash] The decoded message key.
    # @return [Hash|nil] Attribute set for the upserted record. nil to skip
    # insertion.
    def record_attributes(key, payload)
      attributes = @converter.convert(payload)

      attributes.merge(record_key(key))
    end

    # Create an ActiveRecord relation that matches all of the passed
    # records. Used for bulk deletion.
    # @param records [Array<Array>] List of [key, nil] pairs.
    # @return ActiveRecord::Relation Matching relation.
    def deleted_query(records)
      keys = records.
        map { |k, _| record_key(k) }.
        reject(&:empty?)

      keys.reduce(@klass.none) do |query, key|
        query.or(@klass.unscoped.where(key))
      end
    end

    # Get the set of attribute names that uniquely identify messages in the
    # batch. Requires at least one record.
    # @param records [Array<Array>] Non-empty list of [key, value] pairs.
    # @return [Array<String>] List of attribute names.
    # @raise If records is empty.
    def key_columns(records)
      raise 'Cannot determine key from empty batch' if records.empty?

      first_key, = records.first
      record_key(first_key).keys
    end

  private

    # Split the batch into a series of independent slices. Each slice contains
    # messages that can be processed in any order (i.e. they have distinct
    # keys). Messages with the same key will be separated into different
    # slices that maintain the correct order.
    # E.g. Given messages A1, A2, B1, C1, C2, C3, they will be sliced as:
    # [[A1, B1, C1], [A2, C2], [C3]]
    def _slice_batch(messages)
      # If no keys, just one big slice
      if self.class.config[:no_keys]
        return [messages]
      end

      ops = messages.group_by { |k, _| k }

      # Find maximum depth
      depth = ops.values.map(&:length).max || 0

      # Generate slices for each depth
      depth.times.map do |i|
        ops.values.map { |arr| arr.dig(i) }.compact
      end
    end
  end
end
