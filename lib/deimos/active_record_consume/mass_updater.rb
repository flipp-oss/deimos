# frozen_string_literal: true

module Deimos
  module ActiveRecordConsume
    # Responsible for updating the database itself.
    class MassUpdater

      # @param klass [Class < ActiveRecord::Base]
      def default_keys(klass)
        [klass.primary_key]
      end

      # @param klass [Class < ActiveRecord::Base]
      def default_cols(klass)
        klass.column_names - %w(created_at updated_at)
      end

      # @param klass [Class < ActiveRecord::Base]
      # @param key_col_proc [Proc<Class < ActiveRecord::Base>]
      # @param col_proc [Proc<Class < ActiveRecord::Base>]
      # @param replace_associations [Boolean]
      def initialize(klass, key_col_proc: nil, col_proc: nil,
                     replace_associations: true, bulk_import_id_generator: nil, backfill_associations: false,
                     bulk_import_id_column: nil)
        @klass = klass
        @replace_associations = replace_associations
        @bulk_import_id_generator = bulk_import_id_generator
        @backfill_associations = backfill_associations
        @bulk_import_id_column = bulk_import_id_column&.to_s

        @key_cols = {}
        @key_col_proc = key_col_proc

        @columns = {}
        @col_proc = col_proc
      end

      # @param klass [Class < ActiveRecord::Base]
      def columns(klass)
        @columns[klass] ||= @col_proc&.call(klass) || self.default_cols(klass)
      end

      # @param klass [Class < ActiveRecord::Base]
      def key_cols(klass)
        @key_cols[klass] ||= @key_col_proc&.call(klass) || self.default_keys(klass)
      end

      # @param record_list [BatchRecordList]
      def save_records_to_database(record_list, backfill_associations=false)
        columns = self.columns(record_list.klass)
        key_cols = self.key_cols(record_list.klass)
        record_list.records.each(&:validate!)

        options = if @key_cols.empty?
                    {} # Can't upsert with no key, just do regular insert
                  elsif ActiveRecord::Base.connection.adapter_name.downcase =~ /mysql/ ||
                        ActiveRecord::Base.connection.adapter_name.downcase =~ /trilogy/
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
        options[:on_duplicate_key_ignore] = true if backfill_associations
        record_list.klass.import!(columns, record_list.records, options)
      end

      # Imports associated objects and import them to database table
      # The base table is expected to contain bulk_import_id column for indexing associated objects with id
      # @param record_list [BatchRecordList]
      def import_associations(record_list)
        record_list.fill_primary_keys!

        import_id = @replace_associations ? @bulk_import_id_generator&.call : nil
        record_list.associations.each do |assoc|
          sub_records = record_list.map { |r| r.sub_records(assoc.name, import_id) }.flatten
          next unless sub_records.any?

          sub_record_list = BatchRecordList.new(sub_records)

          save_records_to_database(sub_record_list)
          record_list.delete_old_records(assoc, import_id) if import_id
        end
      end

      def backfill_associations(record_list)
        associations = {}
        record_list.associations.each do |a|
          klass = a.name.to_s.capitalize.constantize
          col = @bulk_import_id_column if klass.column_names.include?(@bulk_import_id_column)
          associations[[a.name.to_s, a.name.to_s.capitalize.constantize, col]] = []
        end
        record_list.batch_records.each do |primary_batch_record|
          associations.each_key do |assoc, klass, col|
            batch_record = BatchRecord.new(klass: klass,
                                           attributes: primary_batch_record.associations[assoc],
                                           bulk_import_column: col,
                                           bulk_import_id_generator: @bulk_import_id_generator)
            # Associate this associated batch record's record with the primary record to
            # retrieve foreign_key after associated records have been saved and primary
            # keys have been filled
            primary_batch_record.record.send(:"#{assoc}=", batch_record.record)
            associations[[assoc, klass, col]] << batch_record
          end
        end
        associations.each_value do |records|
          assoc_record_list = BatchRecordList.new(records)
          save_records_to_database(assoc_record_list)
          import_associations(assoc_record_list)
        end
        record_list.records.each do |record|
          associations.each_key do |assoc, _|
            record.send(:"#{assoc}_id=", record.send(assoc.to_sym).id)
          end
        end
      end

      # @param record_list [BatchRecordList]
      # @return [Array<ActiveRecord::Base>]
      def mass_update(record_list)
        # The entire batch should be treated as one transaction so that if
        # any message fails, the whole thing is rolled back or retried
        # if there is deadlock
        Deimos::Utils::DeadlockRetry.wrap(Deimos.config.tracer.active_span.get_tag('topic')) do
          if @backfill_associations
            backfill_associations(record_list)
            save_records_to_database(record_list, true)
          else
            save_records_to_database(record_list)
            import_associations(record_list) if record_list.associations.any?
          end
        end
        record_list.records
      end

    end
  end
end
