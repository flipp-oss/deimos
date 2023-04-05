# frozen_string_literal: true

require 'deimos/active_record_consume/batch_slicer'
require 'deimos/utils/deadlock_retry'
require 'deimos/message'
require 'deimos/exceptions'

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
        elsif self.class.config[:key_field].nil?
          { @klass.primary_key => key }
        else
            { self.class.config[:key_field] => key }
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
        key_cols = key_columns(messages, @klass)

        # Create ActiveRecord Models with payload + key attributes
        upserts = build_records(messages)
        # If overridden record_attributes indicated no record, skip
        upserts.compact!
        # apply ActiveRecord validations and fetch valid Records
        valid_upserts = filter_records(upserts)

        return if valid_upserts.empty?

        save_records_to_database(@klass, key_cols, valid_upserts)
        import_associations(valid_upserts) unless @association_list.blank?
      end

      def save_records_to_database(record_class, key_cols, records)
        columns = columns(record_class)

        options = if key_cols.empty?
                    {} # Can't upsert with no key, just do regular insert
                  elsif mysql_adapter?
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
        record_class.import!(columns, records, options)
      end

      # Imports associated objects and import them to database table
      # The base table is expected to contain bulk_import_id column for indexing associated objects with id
      # @association_list configured on the consumer helps identify the ones required to be saved.
      def import_associations(entities)
        _validate_associations(entities)
        _fill_primary_key_on_entities(entities)
        delete_map = []

        # Select associations from config parameter association_list and
        # fill id to associated_objects foreign_key column
        @klass.reflect_on_all_associations.select { |assoc| @association_list.include?(assoc.name) }.
          each do |assoc|
            sub_records = entities.map { |entity|
              # Get associated `has_one` or `has_many` records for each entity
              sub_records = Array(entity.send(assoc.name))
              # Set IDS from master to each of the records in `has_one` or `has_many` relation
              sub_records.each { |d| d.send("#{assoc.foreign_key}=", entity.send(assoc.active_record_primary_key)) }

              # Retrieve bulk_import_id data to deleting repeated lines
              if entity.attributes['bulk_import_id'].present?
                delete_map.push(
                  'bulk_import_id' => entity.attributes['bulk_import_id'],
                  'primary_key_value' => entity.attributes[assoc.active_record_primary_key],
                  'primary_key_name' => assoc.foreign_key
                )
              end

              sub_records
            }.flatten

            columns = key_columns(nil, assoc.klass)
            save_records_to_database(assoc.klass, columns, sub_records) if sub_records.any?
            removing_repeated_associations(delete_map, columns, assoc.klass)
          end
      end

      def removing_repeated_associations(delete_map, columns, assoc)
        return unless columns.include? 'bulk_import_id' && delete_map.any?

        delete_map.each do |d|
          assoc.unscoped.
            where(d['primary_key_name'] => d['primary_key_value']).
            where.not('bulk_import_id' => d['bulk_import_id']).delete_all
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
      # The parameters are mutually exclusive. records is used by default implementation.
      # @param records [Array<Message>] Non-empty list of messages.
      # @param _klass [ActiveRecord::Class] Class Name can be used to fetch columns
      # @return [Array<String>] List of attribute names.
      # @raise If records is empty.
      def key_columns(records, _klass)
        raise 'Cannot determine key from empty batch' if records.empty?

        first_key = records.first.key
        record_key(first_key).keys
      end

      # Get the list of database table column names that should be saved to the database
      # @param record_class [Class] ActiveRecord class associated to the Entity Object
      # @return Array[String] list of table columns
      def columns(record_class)
        # In-memory records contain created_at and updated_at as nil
        # which messes up ActiveRecord-Import bulk_import.
        # It is necessary to ignore timestamp columns when using ActiveRecord objects
        ignored_columns = %w(created_at updated_at)
        record_class.columns.map(&:name) - ignored_columns
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
      def build_records(messages)
        messages.map do |m|
          attrs = if self.method(:record_attributes).parameters.size == 2
                    record_attributes(m.payload, m.key)
                  else
                    record_attributes(m.payload)
                  end

          attrs = attrs&.merge(record_key(m.key))
          @klass.new(attrs) unless attrs.nil?
        end
      end

      # Filters list of Active Records by applying active record validations.
      # Tip: Add validates_associated in ActiveRecord model to validate associated models
      # Optionally inherit this method and apply more filters in the application code
      # The default implementation throws ActiveRecord::RecordInvalid by default
      # @param records Array<ActiveRecord> - List of active records which will be subjected to model validations
      # @return valid Array<ActiveRecord> - Subset of records that passed the model validations
      def filter_records(records)
        records.each(&:validate!)
      end

      # Returns true if MySQL Adapter is currently used
      def mysql_adapter?
        ActiveRecord::Base.connection.adapter_name.downcase =~ /mysql/
      end

      # Checks whether the entities has necessary columns for `association_list` to work
      # @return void
      def _validate_associations(entities)
        raise Deimos::MissingImplementationError unless mysql_adapter?

        return if entities.first.respond_to?(@bulk_import_id_column)

        raise "Create bulk_import_id on #{entities.first.class} and set it in `build_records` for associations." \
              ' Run rails g deimos:bulk_import_id {table} to create the migration.'
      end

      # Fills Primary Key ID on in-memory objects.
      # Uses @bulk_import_id_column on in-memory records to fetch saved records in database.
      # @return void
      def _fill_primary_key_on_entities(entities)
        table_by_bulk_import_id = @klass.
          where(@bulk_import_id_column => entities.map { |e| e[@bulk_import_id_column] }).
          select(:id, @bulk_import_id_column).
          index_by { |e| e[@bulk_import_id_column] }
        # update IDs in upsert entity
        entities.each { |entity| entity.id = table_by_bulk_import_id[entity[@bulk_import_id_column]].id }
      end
    end
  end
end
