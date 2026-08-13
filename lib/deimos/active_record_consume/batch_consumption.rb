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
      # @raise [BatchFallbackError] if some messages could not be saved even on their own.
      def consume_batch
        filtered = messages.select { |message| process_message?(message) }
        skipped_count = messages.size - filtered.size
        if skipped_count.positive?
          Deimos::Logging.log_debug(
            message: 'Skipping processing of messages in batch',
            skipped_count: skipped_count
          )
        end
        deimos_messages = filtered.map { |p| Deimos::Message.new(p.payload, key: p.key) }

        tag = topic.name
        Deimos.config.tracer.active_span.set_tag('topic', tag)

        Karafka.monitor.instrument('deimos.ar_consumer.consume_batch', { topic: tag }) do
          failures = if @compacted && deimos_messages.map(&:key).compact.any?
                       update_database(compact_messages(deimos_messages))
                     else
                       uncompacted_update(deimos_messages)
                     end

          # Raised only once every slice and group has been attempted, so that a message which
          # can't be persisted never stops the rest of the batch from being saved.
          raise BatchFallbackError, failures if failures.any?
        end

        post_process_batch(deimos_messages)
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

      # Perform any post-processing after a batch has been consumed.
      # Called once per batch with the list of Deimos::Message that were processed (after filtering and compaction).
      # @param messages [Array<Deimos::Message>] The batch of messages that were processed
      # @return [void]
      def post_process_batch(_messages)
        nil
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
      # @return [Array<Array(Message, StandardError)>] messages that could not be saved even on
      #   their own, paired with their error.
      def uncompacted_update(messages)
        BatchSlicer.
          slice(messages).
          flat_map(&method(:update_database))
      end

      # Perform database operations for a group of messages.
      # All messages with payloads are passed to upsert_records.
      # All tombstones messages are passed to remove_records.
      # @param messages [Array<Message>] List of messages.
      # @return [Array<Array(Message, StandardError)>] messages that could not be saved even on
      #   their own, paired with their error.
      def update_database(messages)
        # Find all upserted records (i.e. that have a payload) and all
        # deleted record (no payload)
        removed, upserted = messages.partition { |m| delete_record?(m) }

        max_db_batch_size = self.class.config[:max_db_batch_size]
        upsert_groups = max_db_batch_size ? upserted.each_slice(max_db_batch_size).to_a : [upserted]
        remove_groups = max_db_batch_size ? removed.each_slice(max_db_batch_size).to_a : [removed]

        # Array() so that a consumer which overrode upsert_records back when it returned nothing
        # degrades to "no failures" rather than tripping the BatchFallbackError below.
        upsert_groups.reject(&:empty?).flat_map { |group| Array(upsert_records(group)) } +
          remove_groups.reject(&:empty?).flat_map { |group| remove_group(group) }
      end

      # Upsert any non-deleted records. Everything that operates on the messages - pre-processing,
      # building and filtering records, instrumentation - happens exactly once here; only the
      # database write is retried if it fails, so nothing gets applied twice.
      # @param messages [Array<Message>] List of messages for a group of
      # records to either be updated or inserted.
      # @return [Array<Array(Message, StandardError)>] messages whose records could not be saved
      #   even on their own, paired with their error.
      def upsert_records(messages)
        record_list = build_records(messages)
        invalid = filter_records(record_list)
        if invalid.any?
          Karafka.monitor.instrument('deimos.batch_consumption.invalid_records', {
                                       records: invalid,
                                       consumer: self.class
                                     })
        end
        return [] if record_list.empty?

        key_col_proc = self.method(:key_columns).to_proc
        col_proc = self.method(:columns).to_proc

        updater = MassUpdater.new(@klass,
                                  key_col_proc: key_col_proc,
                                  col_proc: col_proc,
                                  replace_associations: self.replace_associations,
                                  bulk_import_id_generator: self.bulk_import_id_generator,
                                  save_associations_first: self.save_associations_first,
                                  bulk_import_id_column: self.bulk_import_id_column)
        saved, failures = save_record_list(record_list, updater)
        Karafka.monitor.instrument('deimos.batch_consumption.valid_records', {
                                     records: saved,
                                     consumer: self.class
                                   })
        failures
      end

      # Write a list of records to the database. The list is written in a single statement inside
      # a single transaction, so one record which can't be persisted would otherwise take down
      # every other record written alongside it. Unless the topic turns
      # `fallback_to_individual_updates` off, retry the write one record at a time so the healthy
      # ones still land - and only the write, so that message-level work isn't repeated.
      # @param record_list [BatchRecordList]
      # @param updater [MassUpdater]
      # @return [Array(Array<ActiveRecord::Base>, Array<Array(Message, StandardError)>)] the
      #   records that were saved, and the messages that could not be saved with their error.
      def save_record_list(record_list, updater)
        [updater.mass_update(record_list), []]
      rescue StandardError => e
        raise unless self.fallback_to_individual_updates
        # Nothing to isolate from a single record, and deadlocks/lock wait timeouts are transient
        # contention on the whole write which DeadlockRetry has already retried - they don't point
        # at a bad record, so retrying row by row only multiplies the work.
        raise if record_list.batch_records.size <= 1 || Deimos::Utils::DeadlockRetry.deadlock?(e)

        save_records_individually(record_list, updater, e)
      end

      # @param record_list [BatchRecordList]
      # @param updater [MassUpdater]
      # @param batch_error [StandardError] the error the bulk write raised.
      # @return [Array(Array<ActiveRecord::Base>, Array<Array(Message, StandardError)>)]
      def save_records_individually(record_list, updater, batch_error)
        report_initial_failure(:upsert_records, record_list.batch_records.size, batch_error)

        saved = []
        failures = []
        record_list.batch_records.each do |batch_record|
          saved.concat(updater.mass_update(BatchRecordList.new([batch_record])))
        rescue StandardError => e
          failures << [batch_record.message, e]
        end

        # Nothing could be saved on its own, so this was never about one bad record - it's
        # something systemic (the database is unreachable, ...). The original error describes that
        # better than a BatchFallbackError listing every key.
        raise batch_error if saved.empty?

        [saved, failures]
      end

      # Delete the records for a group of tombstones, falling back to one message at a time if the
      # bulk delete fails. Unlike upserts there is no record building, pre-processing or
      # instrumentation on this path, so the whole operation can safely be retried per message.
      # @param messages [Array<Message>]
      # @return [Array<Array(Message, StandardError)>]
      def remove_group(messages)
        remove_records(messages)
        []
      rescue StandardError => e
        raise unless self.fallback_to_individual_updates
        raise if messages.size <= 1 || Deimos::Utils::DeadlockRetry.deadlock?(e)

        report_initial_failure(:remove_records, messages.size, e)

        failures = []
        messages.each do |message|
          remove_records([message])
        rescue StandardError => individual_error
          failures << [message, individual_error]
        end
        raise e if failures.size == messages.size

        failures
      end

      # Log and announce that a bulk write failed and is about to be retried one at a time.
      # @param operation [Symbol] `:upsert_records` or `:remove_records`.
      # @param count [Integer] how many records or messages were in the failed write.
      # @param error [StandardError]
      # @return [void]
      def report_initial_failure(operation, count, error)
        Deimos::Logging.log_warn(
          message: 'Batch database write failed, retrying one at a time',
          handler: self.class.name,
          topic: self.topic.name,
          operation: operation,
          count: count,
          error_message: error.message
        )
        Karafka.monitor.instrument('deimos.batch_consumption.initial_failure', {
                                     consumer: self.class,
                                     topic: self.topic.name,
                                     operation: operation,
                                     count: count,
                                     error: error
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

          record = BatchRecord.new(klass: @klass,
                                   attributes: attrs,
                                   bulk_import_column: col,
                                   bulk_import_id_generator: self.bulk_import_id_generator)
          # Keep the message so a record which can't be saved can be reported by its Kafka key.
          record.message = m
          record
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
