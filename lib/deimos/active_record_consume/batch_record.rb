# frozen_string_literal: true

module Deimos
  module ActiveRecordConsume
    # Keeps track of both an ActiveRecord instance and more detailed attributes.
    # The attributes are needed for nested associations.
    class BatchRecord
      # @return [ActiveRecord::Base]
      attr_accessor :record
      # @return [Hash] a set of association information, represented by a hash of attributes.
      # For has_one, the format would be e.g. { 'detail' => { 'foo' => 'bar'}}. For has_many, it would
      # be an array, e.g. { 'details' => [{'foo' => 'bar'}, {'foo' => 'baz'}]}
      attr_accessor :associations
      # @return [String] A unique UUID used to associate the auto-increment ID back to
      # the in-memory record.
      attr_accessor :bulk_import_id
      # @return [String] The column name to use for bulk IDs - defaults to `bulk_import_id`.
      attr_accessor :bulk_import_column

      delegate :valid?, :errors, :send, :attributes, to: :record

      # @param klass [Class < ActiveRecord::Base]
      # @param attributes [Hash] the full attribute list, including associations.
      # @param bulk_import_column [String]
      # @param bulk_import_id_generator [Proc]
      def initialize(klass:, attributes:, bulk_import_column: nil, bulk_import_id_generator: nil)
        @klass = klass
        if bulk_import_column
          self.bulk_import_column = bulk_import_column
          self.bulk_import_id = bulk_import_id_generator&.call
          attributes[bulk_import_column] = bulk_import_id
        end
        attributes = attributes.with_indifferent_access
        self.record = klass.new(attributes.slice(*klass.column_names))
        assoc_keys = attributes.keys.select { |k| klass.reflect_on_association(k) }
        # a hash with just the association keys, removing all actual column information.
        self.associations = attributes.slice(*assoc_keys)
        validate_import_id! if self.associations.any?
      end

      # Checks whether the entities has necessary columns for association saving to work
      # @return void
      def validate_import_id!
        return if @klass.column_names.include?(self.bulk_import_column.to_s)

        raise "Create bulk_import_id on the #{@klass.table_name} table. " \
              'Run rails g deimos:bulk_import_id {table} to create the migration.'
      end

      # @return [Class < ActiveRecord::Base]
      def klass
        self.record.class
      end

      # Create a list of BatchRecord instances representing associated objects for the given
      # association name.
      # @param assoc_name [String]
      # @param bulk_import_id [String] A UUID which should be set on *every* sub-record. Unlike the
      # parent bulk_insert_id, where each record has a unique UUID,
      # this is used to detect and delete old data, so this is basically a "session ID" for this
      # bulk upsert.
      # @return [Array<BatchRecord>]
      def sub_records(assoc_name, bulk_import_id=nil)
        attr_list = self.associations[assoc_name.to_s]
        assoc = self.klass.reflect_on_association(assoc_name)
        Array.wrap(attr_list).map { |attrs|
          # Set the ID of the original object, e.g. widgets -> details, this will set widget_id.
          attrs[assoc.foreign_key] = self.record[assoc.active_record_primary_key]
          if bulk_import_id
            attrs[self.bulk_import_column] = bulk_import_id
          end
          BatchRecord.new(klass: assoc.klass, attributes: attrs) if attrs
        }.compact
      end

      # @return [String,Integer]
    end
  end
end
