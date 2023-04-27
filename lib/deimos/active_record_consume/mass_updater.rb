# frozen_string_literal: true

module Deimos
  module ActiveRecordConsume
    # Responsible for updating the database itself.
    class MassUpdater

      # @param klass [Class < ActiveRecord::Base]
      def default_keys(klass)
        klass.connection.
          indexes(klass.table_name).
          select(&:unique).
          map(&:columns).
          flatten
      end

      # @param klass [Class < ActiveRecord::Base]
      def default_cols(klass)
        klass.column_names - %w(created_at updated_at)
      end

      # @param klass [Class < ActiveRecord::Base]
      # @param key_col_proc [Proc<Class < ActiveRecord::Base>]
      # @param col_proc [Proc<Class < ActiveRecord::Base>]
      # @param replace_associations [Boolean]
      def initialize(klass, key_col_proc: nil, col_proc: nil, replace_associations: true)
        @klass = klass
        @replace_associations = replace_associations

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
        record_list.klass.import!(columns, record_list.records, options)
      end

      # Imports associated objects and import them to database table
      # The base table is expected to contain bulk_import_id column for indexing associated objects with id
      # @param record_list [BatchRecordList]
      def import_associations(record_list)
        record_list.validate_associations!
        record_list.fill_primary_keys!

        import_id = @replace_associations ? SecureRandom.uuid : nil
        record_list.associations.each do |assoc|
          sub_records = record_list.map { |r| r.sub_records(assoc.name, import_id) }.flatten
          next unless sub_records.any?

          sub_record_list = BatchRecordList.new(sub_records)

          save_records_to_database(sub_record_list)
          record_list.delete_old_records(assoc, import_id) if import_id
        end
      end

      # @param record_list [BatchRecordList]
      def mass_update(record_list)
        save_records_to_database(record_list)
        import_associations(record_list) if record_list.associations.any?
      end

    end
  end
end
