# frozen_string_literal: true

module Deimos
  module ActiveRecord
    # Batch consume methods
    module BatchConsumption
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
          _retry_deadlock(topic: metadata[:topic]) do
            ::ActiveRecord::Base.transaction do
              slices.each do |slice|
                removed, upserted = slice.partition { |_, v| v.nil? }

                upsert_records(upserted) if upserted.any?
                remove_records(removed) if removed.any?
              end
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

        messages = records.map do |k, v|
          record = record_attributes(v, k)
          record.merge(record_key(k))
        end

        # If record_attributes indicated no record, skip it
        messages.compact!

        options = if key_cols.empty?
                    {} # Can't upsert with no key, just do regular insert
                  else
                    {
                      on_duplicate_key_update: {
                        # conflict_target must explicitly list the columns for
                        # Postgres and SQLite. Not required for MySQL,
                        # but it will behave the same as being unset
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

      # Maximum number of times to retry a block after encountering a deadlock
      RETRY_COUNT = 2

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

      # Retry the given block when encountering a deadlock. For any other
      # exceptions, they are reraised. This is used to handle cases where
      # the database may be busy but the transaction would succeed if
      # retried later.
      def _retry_deadlock(tags=[])
        count = RETRY_COUNT

        begin
          yield
        rescue ::ActiveRecord::Deadlocked => e
          raise e if count <= 0

          Rails.logger.warn(
            message: 'Deadlock encountered when trying to execute query. '\
              "Retrying. #{count} attempt(s) remaining",
            tags: tags
          )

          Deimos.config.metrics&.increment(
            'deadlock',
            tags: tags
          )

          count -= 1
          retry
        end
      end
    end
  end
end
