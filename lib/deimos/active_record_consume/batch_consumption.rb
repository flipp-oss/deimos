# frozen_string_literal: true

require 'deimos/active_record_consume/batch_slicer'
require 'deimos/active_record_consume/batch_record'
require 'deimos/active_record_consume/batch_record_list'
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

    protected

      # Get unique key for the ActiveRecord instance from the incoming key.
      # Override this method (with super) to customize the set of attributes that
      # uniquely identifies each record in the database.
      # @param key [String,Hash] The encoded key.
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

      # @param _record [ActiveRecord::Base]
      # @return [Boolean]
      def should_consume?(_record)
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
        key_cols = key_columns(messages, @klass)

        record_list = build_records(messages)
        record_list.filter!(self.method(:should_consume?).to_proc)

        return if record_list.empty?

        save_records_to_database(@klass, key_cols, record_list)
        import_associations(record_list) if record_list.associations.any?
      end

      # @param messages [Array<Deimos::Message>]
      # @return [BatchRecordList]
      def build_records(messages)
        records = messages.map do |m|
          attrs = if self.method(:record_attributes).parameters.size == 2
                    record_attributes(m.payload, m.key)
                  else
                    record_attributes(m.payload)
                  end
          next nil if attrs.nil?

          attrs = attrs.merge(record_key(m.key))
          next unless attrs

          BatchRecord.new(klass: @klass,
                          attributes: attrs,
                          bulk_import_column: self.class.bulk_import_id_column)
        end
        BatchRecordList.new(records.compact)
      end

      # @param record_class [Class < ActiveRecord::Base]
      # @param key_cols [Array<String>]
      # @param record_list [BatchRecordList]
      def save_records_to_database(record_class, key_cols, record_list)
        record_list.records.each(&:validate!)
        columns = columns(record_class)

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
        record_class.import!(columns, record_list.records, options)
      end

      # Imports associated objects and import them to database table
      # The base table is expected to contain bulk_import_id column for indexing associated objects with id
      # @param record_list [BatchRecordList]
      def import_associations(record_list)
        validate_associations!
        record_list.fill_primary_keys!

        import_id = self.class.config[:replace_associations] ? SecureRandom.uuid : nil
        primary_keys = record_list.primary_keys
        record_list.associations.each do |assoc|
          sub_records = record_list.map { |r| r.sub_records(assoc.name, import_id) }.flatten
          sub_record_list = BatchRecordList.new(sub_records)

          columns = key_columns(nil, assoc.klass)
          if sub_records.any?
            save_records_to_database(assoc.klass, columns, sub_record_list)
            delete_old_records(assoc, import_id, primary_keys) if import_id
          end
        end
      end

      # Checks whether the entities has necessary columns for association saving to work
      # @return void
      def validate_associations!
        return if @klass.column_names.include?(self.class.bulk_import_id_column.to_s)

        raise "Create bulk_import_id on the #{@klass.table_name} table." \
              ' Run rails g deimos:bulk_import_id {table} to create the migration.'
      end

      # @param assoc [ActiveRecord::Reflection::AssociationReflection]
      # @param import_id [String]
      # @param primary_keys [Array<String,Integer>]
      def delete_old_records(assoc, import_id, primary_keys)
        assoc.klass.
          where(assoc.foreign_key => primary_keys).
          where("#{self.class.bulk_import_id_column} != ?", import_id).
          delete_all
      end

      # Delete any records with a tombstone.
      # @param messages [Array<Message>] List of messages for a group of
      # deleted records.
      # @return [void]
      def remove_records(messages)
        clause = deleted_query(messages)

        clause.delete_all
      end
    end
  end
end
