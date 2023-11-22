# frozen_string_literal: true

module Deimos
  module ActiveRecordConsume
    # A set of BatchRecords which typically are worked with together (hence the batching!)
    class BatchRecordList
      # @return [Array<BatchRecord>]
      attr_accessor :batch_records
      attr_accessor :klass, :bulk_import_column

      delegate :empty?, :map, to: :batch_records

      # @param records [Array<BatchRecord>]
      def initialize(records)
        self.batch_records = records
        self.klass = records.first&.klass
        self.bulk_import_column = records.first&.bulk_import_column&.to_sym
      end

      # Filter out any invalid records.
      # @param method [Proc]
      def filter!(method)
        self.batch_records.delete_if { |record| !method.call(record.record) }
      end

      # Partition batch records by the given block
      # @param block [Proc]
      def partition(&block)
        self.batch_records.partition(&block)
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
        @associations = self.klass.reflect_on_all_associations.select { |assoc| keys.include?(assoc.name) }
      end

      # Go back to the DB and use the bulk_import_id to set the actual primary key (`id`) of the
      # records.
      def fill_primary_keys!
        primary_col = self.klass.primary_key
        bulk_import_map = self.klass.
          where(self.bulk_import_column => self.batch_records.map(&:bulk_import_id)).
          select(primary_col, self.bulk_import_column).
          index_by(&self.bulk_import_column).to_h
        self.batch_records.each do |r|
          r.record[primary_col] = bulk_import_map[r.bulk_import_id][primary_col]
        end
      end

      # @param [String] assoc_name
      # @return [Array<Integer,String>]
      def primary_keys(assoc_name)
        assoc = self.associations.find { |a| a.name == assoc_name }
        self.records.map do |record|
          record[assoc.active_record_primary_key]
        end
      end

      # @param assoc [ActiveRecord::Reflection::AssociationReflection]
      # @param import_id [String]
      def delete_old_records(assoc, import_id)
        return if self.batch_records.none?

        primary_keys = self.primary_keys(assoc.name)
        assoc.klass.
          where(assoc.foreign_key => primary_keys).
          where("#{self.bulk_import_column} != ?", import_id).
          delete_all
      end

    end
  end
end
