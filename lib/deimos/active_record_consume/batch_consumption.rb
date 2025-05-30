# frozen_string_literal: true

require 'deimos/active_record_consume/batch_slicer'
require 'deimos/active_record_consume/batch_record'
require 'deimos/active_record_consume/batch_record_list'
require 'deimos/active_record_consume/mass_updater'
require 'deimos/consume/batch_consumption'

require 'deimos/utils/deadlock_retry'
require 'deimos/message'
require 'deimos/exceptions'

module Deimos
  module ActiveRecordConsume
    # Methods for consuming batches of messages and saving them to the database
    # in bulk ActiveRecord operations.
    module BatchConsumption
      include Deimos::Consume::BatchConsumption

      # Handle a batch of Kafka messages. Batches are split into "slices",
      # which are groups of independent messages that can be processed together
      # in a single database operation.
      # If two messages in a batch have the same key, we cannot process them
      # in the same operation as they would interfere with each other. Thus
      # they are split
      # @return [void]
      def consume_batch
        deimos_messages = messages.map { |p| Deimos::Message.new(p.payload, key: p.key) }

        tag = topic.name
        Deimos.config.tracer.active_span.set_tag('topic', tag)

        Karafka.monitor.instrument('deimos.ar_consumer.consume_batch', {topic: tag}) do
          if @compacted && deimos_messages.map(&:key).compact.any?
            update_database(compact_messages(deimos_messages))
          else
            uncompacted_update(deimos_messages)
          end
        end
      end

    protected

      # Get the set of attribute names that uniquely identify messages in the
      # batch. Requires at least one record.
      # The parameters are mutually exclusive. records is used by default implementation.
      # @param _klass [Class < ActiveRecord::Base] Class Name can be used to fetch columns
      # @return [Array<String>,nil] List of attribute names.
      # @raise If records is empty.
      def key_columns(_klass)
        nil
      end

      # Get the list of database table column names that should be saved to the database
      # @param _klass [Class < ActiveRecord::Base] ActiveRecord class associated to the Entity Object
      # @return [Array<String>,nil] list of table columns
      def columns(_klass)
        nil
      end

      # Get unique key for the ActiveRecord instance from the incoming key.
      # Override this method (with super) to customize the set of attributes that
      # uniquely identifies each record in the database.
      # @param key [String,Hash] The encoded key.
      # @return [Hash] The key attributes.
      def record_key(key)
        if key.nil?
          {}
        elsif key.is_a?(Hash) || key.is_a?(SchemaClass::Record)
          self.key_converter.convert(key)
        elsif self.topic.key_config[:field].nil?
          { @klass.primary_key => key }
        else
          { self.topic.key_config[:field].to_s => key }
        end
      end

      # Create an ActiveRecord relation that matches all of the passed
      # records. Used for bulk deletion.
      # @param records [Array<Message>] List of messages.
      # @return [ActiveRecord::Relation] Matching relation.
      def deleted_query(records)
        keys = records.
          map { |m| record_key(m.key)[@klass.primary_key] }.
          compact

        @klass.unscoped.where(@klass.primary_key => keys)
      end

      # @param _record [ActiveRecord::Base]
      # @param _associations [Hash]
      # @return [Boolean]
      def should_consume?(_record, _associations=nil)
        true
      end

    private

      # Compact a batch of messages, taking only the last message for each
      # unique key.
      # @param batch [Array<Message>] Batch of messages.
      # @return [Array<Message>] Compacted batch.
      def compact_messages(batch)
        return batch unless batch.first&.key.present?

        batch.reverse.uniq(&:key).reverse!
      end

      # Perform database operations for a batch of messages without compaction.
      # All messages are split into slices containing only unique keys, and
      # each slice is handles as its own batch.
      # @param messages [Array<Message>] List of messages.
      # @return [void]
      def uncompacted_update(messages)
        BatchSlicer.
          slice(messages).
          each(&method(:update_database))
      end

      # Perform database operations for a group of messages.
      # All messages with payloads are passed to upsert_records.
      # All tombstones messages are passed to remove_records.
      # @param messages [Array<Message>] List of messages.
      # @return [void]
      def update_database(messages)
        # Find all upserted records (i.e. that have a payload) and all
        # deleted record (no payload)
        removed, upserted = messages.partition(&:tombstone?)

        max_db_batch_size = self.class.config[:max_db_batch_size]
        if upserted.any?
          if max_db_batch_size
            upserted.each_slice(max_db_batch_size) { |group| upsert_records(group) }
          else
            upsert_records(upserted)
          end
        end

        return if removed.empty?

        if max_db_batch_size
          removed.each_slice(max_db_batch_size) { |group| remove_records(group) }
        else
          remove_records(removed)
        end
      end

      # Upsert any non-deleted records
      # @param messages [Array<Message>] List of messages for a group of
      # records to either be updated or inserted.
      # @return [void]
      def upsert_records(messages)
        record_list = build_records(messages)
        invalid = filter_records(record_list)
        if invalid.any?
          Karafka.monitor.instrument('deimos.batch_consumption.invalid_records', {
            records: invalid,
            consumer: self.class
          })
        end
        return if record_list.empty?

        key_col_proc = self.method(:key_columns).to_proc
        col_proc = self.method(:columns).to_proc

        updater = MassUpdater.new(@klass,
                                  key_col_proc: key_col_proc,
                                  col_proc: col_proc,
                                  replace_associations: self.replace_associations,
                                  bulk_import_id_generator: self.bulk_import_id_generator,
                                  save_associations_first: self.save_associations_first,
                                  bulk_import_id_column: self.bulk_import_id_column)
        Karafka.monitor.instrument('deimos.batch_consumption.valid_records', {
          records: updater.mass_update(record_list),
          consumer: self.class
        })
      end

      # @param record_list [BatchRecordList]
      # @return [Array<BatchRecord>]
      def filter_records(record_list)
        record_list.filter!(self.method(:should_consume?).to_proc)
      end

      # Process messages prior to saving to database
      # @param _messages [Array<Deimos::Message>]
      # @return [Void]
      def pre_process(_messages)
        nil
      end

      # @param messages [Array<Deimos::Message>]
      # @return [BatchRecordList]
      def build_records(messages)
        pre_process(messages)
        records = messages.map do |m|
          attrs = if self.method(:record_attributes).parameters.size == 2
                    record_attributes(m.payload, m.key)
                  else
                    record_attributes(m.payload)
                  end
          next nil if attrs.nil?

          attrs = attrs.merge(record_key(m.key))
          next unless attrs

          col = if @klass.column_names.include?(self.bulk_import_id_column.to_s)
                  self.bulk_import_id_column
                end

          BatchRecord.new(klass: @klass,
                          attributes: attrs,
                          bulk_import_column: col,
                          bulk_import_id_generator: self.bulk_import_id_generator)
        end
        BatchRecordList.new(records.compact)
      end

      # Delete any records with a tombstone.
      # @param messages [Array<Message>] List of messages for a group of
      # deleted records.
      # @return [void]
      def remove_records(messages)
        Deimos::Utils::DeadlockRetry.wrap(Deimos.config.tracer.active_span.get_tag('topic')) do
          clause = deleted_query(messages)

          clause.delete_all
        end
      end
    end
  end
end
