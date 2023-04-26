module Deimos
  module ActiveRecordConsume

    # A set of BatchRecords which typically are worked with together (hence the batching!)
    class BatchRecordList
      # @return [Array<BatchRecord>]
      attr_accessor :batch_records

      delegate :empty?, :map, to: :batch_records

      # @param records [Array<BatchRecord>]
      def initialize(records)
        self.batch_records = records
        @klass = records.first&.klass
        @bulk_import_column = records.first&.bulk_import_column
      end

      # Filter out any invalid records.
      # @param method [Proc]
      def filter!(method)
        self.batch_records.delete_if { |record| !method.call(record.record) }
      end

      # Get the original ActiveRecord objects.
      # @return [Array<ActiveRecord::Base>]
      def records
        self.batch_records.map(&:record)
      end

      # Get the list of relevant associations, based on the keys of the association hashes of all
      # records in this list.
      # @return [Array<ActiveRecord::Reflection::AssociationReflection>]
      def associations
        return @associations if @associations

        keys = self.batch_records.map { |r| r.associations.keys }.flatten.uniq.map(&:to_sym)
        @associations = @klass.reflect_on_all_associations.select { |assoc| keys.include?(assoc.name) }
      end

      # Go back to the DB and use the bulk_import_id to set the actual primary key (`id`) of the
      # records.
      def fill_primary_keys!
        primary_col = @klass.primary_key
        bulk_import_map = @klass.
          where(@bulk_import_column => self.batch_records.map(&:bulk_import_id)).
          select(primary_col, @bulk_import_column).
          index_by(&@bulk_import_column)
        self.batch_records.each do |r|
          r.record[primary_col] = bulk_import_map[r.bulk_import_id][primary_col]
        end
      end

      # @return [Array<Integer,String>]
      def primary_keys
        self.batch_records.map(&:primary_key)
      end

    end
  end
end

