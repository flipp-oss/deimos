# frozen_string_literal: true

require 'deimos/active_record_consume/batch_slicer'
require 'deimos/utils/deadlock_retry'
require 'deimos/message'

module Deimos
  module ActiveRecordConsume
    # Methods for consuming batches of messages and saving them to the database
    # in bulk ActiveRecord operations.
    module BatchConsumption
      # Handle a batch of Kafka messages. Batches are split into "slices",
      # which are groups of independent messages that can be processed together
      # in a single database operation.
      # If two messages in a batch have the same key, we cannot process them
      # in the same operation as they would interfere with each other. Thus
      # they are split
      # @param payloads [Array<Hash,Deimos::SchemaClass::Record>] Decoded payloads
      # @param metadata [Hash] Information about batch, including keys.
      # @return [void]
      def consume_batch(payloads, metadata)
        messages = payloads.
          zip(metadata[:keys]).
          map { |p, k| Deimos::Message.new(p, nil, key: k) }

        tags = %W(topic:#{metadata[:topic]})

        Deimos.instrument('ar_consumer.consume_batch', tags) do
          # The entire batch should be treated as one transaction so that if
          # any message fails, the whole thing is rolled back or retried
          # if there is deadlock
          Deimos::Utils::DeadlockRetry.wrap(tags) do
            if @compacted || self.class.config[:no_keys]
              update_database(compact_messages(messages))
            else
              uncompacted_update(messages)
            end
          end
        end
      end

      # Get unique key for the ActiveRecord instance from the incoming key.
      # Override this method (with super) to customize the set of attributes that
      # uniquely identifies each record in the database.
      # @param key [String] The encoded key.
      # @return [Hash] The key attributes.
      def record_key(key)
        if key.nil?
          {}
        elsif key.is_a?(Hash)
          @key_converter.convert(key)
        else
          { @klass.primary_key => key }
        end
      end

    protected

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

        upsert_records(upserted) if upserted.any?
        remove_records(removed) if removed.any?
      end

      # Upsert any non-deleted records
      # @param messages [Array<Message>] List of messages for a group of
      # records to either be updated or inserted.
      # @return [void]
      def upsert_records(messages)
        key_cols = key_columns(messages)

        # Create ActiveRecord Models with payload + key attributes
        upserts = build_models(messages)
        # If overridden record_attributes indicated no record, skip
        upserts.compact!
        # apply ActiveRecord validations and fetch valid Records
        valid_upserts = filter_models(upserts)

        save_records_to_database(@klass, key_cols, valid_upserts)

        import_associations(valid_upserts, key_cols) unless @association_list.empty?
      end

      def save_records_to_database(record_class, key_cols, records)
        columns = :all
        if record_class.respond_to?(:bulk_import_columns)
          columns = record_class.bulk_import_columns
        end

        options = if key_cols.empty?
                    {} # Can't upsert with no key, just do regular insert
                  elsif ActiveRecord::Base.connection.adapter_name.downcase =~ /mysql/
                    {
                      on_duplicate_key_update: columns
                    }
                  else
                    {
                      on_duplicate_key_update: {
                        conflict_target: key_cols,
                        columns: columns
                      }
                    }
                  end

        if @klass.respond_to?(:bulk_import_columns)
          @klass.import!(columns, records, options)
        else
          @klass.import!(records, options)
        end

      end
      # config for associations
      # bulk_import_id is required only if handle_associations is set to true
      # alternatively set a config to add which associations need to be considered
      # There could be many associations not relevant to master table. For example, products and merchant association
      def import_associations(entities)
        associations = @klass.reflect_on_all_associations.select { |assoc| @association_list.include?(assoc.name) }

        # create DB migration for bulk insert id. I did it manually in item-platform
        table_by_bulk_import_id =
          @klass.where(bulk_import_id: entities.map(&:bulk_import_id)).
            select(:id, :bulk_import_id).
            index_by(&:bulk_import_id)
        # update IDs in master table
        entities.each { |entity| entity.id = table_by_bulk_import_id[entity.bulk_import_id].id }
        associations.each do |assoc|
          details = entities.map { |master|
            details = master.send(assoc.name)
            unless details.is_a?(Enumerable)
              details = [details]
            end
            details.each { |d| d.send("#{assoc.send(:foreign_key)}=", master.id) }

            details.to_a
          }.flatten

          save_records_to_database(assoc.klass, assoc.klass.bulk_update_columns, details) unless details.empty?
        end
      end

      # Delete any records with a tombstone.
      # @param messages [Array<Message>] List of messages for a group of
      # deleted records.
      # @return [void]
      def remove_records(messages)
        clause = deleted_query(messages)

        clause.delete_all
      end

      # Create an ActiveRecord relation that matches all of the passed
      # records. Used for bulk deletion.
      # @param records [Array<Message>] List of messages.
      # @return [ActiveRecord::Relation] Matching relation.
      def deleted_query(records)
        keys = records.
          map { |m| record_key(m.key)[@klass.primary_key] }.
          reject(&:nil?)

        @klass.unscoped.where(@klass.primary_key => keys)
      end

      # Get the set of attribute names that uniquely identify messages in the
      # batch. Requires at least one record.
      # @param records [Array<Message>] Non-empty list of messages.
      # @return [Array<String>] List of attribute names.
      # @raise If records is empty.
      def key_columns(records)
        raise 'Cannot determine key from empty batch' if records.empty?

        first_key = records.first.key
        record_key(first_key).keys
      end

      # Compact a batch of messages, taking only the last message for each
      # unique key.
      # @param batch [Array<Message>] Batch of messages.
      # @return [Array<Message>] Compacted batch.
      def compact_messages(batch)
        return batch unless batch.first&.key.present?

        batch.reverse.uniq(&:key).reverse!
      end

      # Turns Kafka payload into ActiveRecord Objects by mapping relevant fields
      # Override this method to build object and associations with message payload
      # @param messages [Array<Deimos::Message>] the array of deimos messages in batch mode
      # @return [Array<ActiveRecord>] Array of ActiveRecord objects
      def build_models(messages)
        messages.map do |m|
          attrs = if self.method(:record_attributes).parameters.size == 2
                    record_attributes(m.payload, m.key)
                  else
                    record_attributes(m.payload)
                  end

          attrs&.merge(record_key(m.key))
          @klass.new(attrs)
        end
      end

      # Filters list of Active Records by applying active record validations. Optionally, validation_context can
      # be set in ActiveRecordConsumer to override the default `nil` context.
      # Tip: Add validates_associated in ActiveRecord model to validate associated_models
      # Optionally inherit this method and apply more filters in the application code
      # @param records Array<ActiveRecord> - List of active records which will be subjected to model validations
      # @return valid Array<ActiveRecord> - Subset of records that passed the model validations
      def filter_models(records)
        valid, invalid = records.partition do |p|
          p.valid?(@validation_context)
        end
        invalid.each do |entity|
          Deimos.config.logger.info('DB Validation failed --'\
                                "Attributes: #{entity.attributes},"\
                                " Errors:#{entity.errors.full_messages}")
        end
        valid
      end
    end
  end
end
