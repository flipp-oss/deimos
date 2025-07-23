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
                     replace_associations: true, bulk_import_id_generator: nil, save_associations_first: false,
                     bulk_import_id_column: nil,
                     fill_primary_key: true)
        @klass = klass
        @replace_associations = replace_associations
        @bulk_import_id_generator = bulk_import_id_generator
        @save_associations_first = save_associations_first
        @bulk_import_id_column = bulk_import_id_column&.to_s
        @fill_primary_key = fill_primary_key

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
      def save_records_to_database(record_list)
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
        record_list.klass.import!(columns, record_list.records, options)
      end

      # Imports associated objects and import them to database table
      # The base table is expected to contain bulk_import_id column for indexing associated objects with id
      # @param record_list [BatchRecordList]
      def import_associations(record_list)
        record_list.fill_primary_keys! if @fill_primary_key

        import_id = @replace_associations ? @bulk_import_id_generator&.call : nil
        record_list.associations.each do |assoc|
          sub_records = record_list.map { |r| r.sub_records(assoc.name, import_id) }.flatten
          next unless sub_records.any?

          sub_record_list = BatchRecordList.new(sub_records)

          save_records_to_database(sub_record_list)
          record_list.delete_old_records(assoc, import_id) if import_id
        end
      end

      # Assign associated records to corresponding primary records
      # @param record_list [BatchRecordList] RecordList of primary records for this consumer
      # @return [Hash]
      def assign_associations(record_list)
        associations_info = {}
        record_list.associations.each do |assoc|
          col = @bulk_import_id_column if assoc.klass.column_names.include?(@bulk_import_id_column)
          associations_info[[assoc, col]] = []
        end
        record_list.batch_records.each do |primary_batch_record|
          associations_info.each_key do |assoc, col|
            batch_record = BatchRecord.new(klass: assoc.klass,
                                           attributes: primary_batch_record.associations[assoc.name],
                                           bulk_import_column: col,
                                           bulk_import_id_generator: @bulk_import_id_generator)
            # Associate this associated batch record's record with the primary record to
            # retrieve foreign_key after associated records have been saved and primary
            # keys have been filled
            primary_batch_record.record.assign_attributes({ assoc.name => batch_record.record })
            associations_info[[assoc, col]] << batch_record
          end
        end
        associations_info
      end

      # Save associated records and fill foreign keys on RecordList records
      # @param record_list [BatchRecordList] RecordList of primary records for this consumer
      # @param associations_info [Hash] Contains association info
      def save_associations_first(record_list, associations_info)
        associations_info.each_value do |records|
          assoc_record_list = BatchRecordList.new(records)
          Deimos::Utils::DeadlockRetry.wrap(Deimos.config.tracer.active_span.get_tag('topic')) do
            save_records_to_database(assoc_record_list)
          end
          import_associations(assoc_record_list)
        end
        record_list.records.each do |record|
          associations_info.each_key do |assoc, _|
            record.assign_attributes({ assoc.foreign_key => record.send(assoc.name).id })
          end
        end
      end

      # @param record_list [BatchRecordList]
      # @return [Array<ActiveRecord::Base>]
      def mass_update(record_list)
        # The entire batch should be treated as one transaction so that if
        # any message fails, the whole thing is rolled back or retried
        # if there is deadlock

        if @save_associations_first
          associations_info = assign_associations(record_list)
          save_associations_first(record_list, associations_info)
          Deimos::Utils::DeadlockRetry.wrap(Deimos.config.tracer.active_span.get_tag('topic')) do
            save_records_to_database(record_list)
          end
        else
          Deimos::Utils::DeadlockRetry.wrap(Deimos.config.tracer.active_span.get_tag('topic')) do
            save_records_to_database(record_list)
            import_associations(record_list) if record_list.associations.any?
          end
        end
        record_list.records
      end

    end
  end
end
