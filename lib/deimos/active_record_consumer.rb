# frozen_string_literal: true

require 'deimos/consumer'

module Deimos
  # Consumer that automatically saves the payload into the database.
  class ActiveRecordConsumer < Consumer
    class << self
      # param klass [Class < ActiveRecord::Base] the class used to save to the
      # database.
      def record_class(klass)
        config[:record_class] = klass
      end
    end

    # :nodoc:
    def consume(payload, metadata)
      key = metadata.with_indifferent_access[:key]
      klass = self.class.config[:record_class]
      record = klass.where(klass.primary_key => key).first
      if payload.nil?
        destroy_record(record)
        return
      end
      record ||= klass.new
      attrs = record_attributes(payload.with_indifferent_access)
      # don't use attributes= - bypass Rails < 5 attr_protected
      attrs.each do |k, v|
        record.send("#{k}=", v)
      end
      record[klass.primary_key] = key
      record.created_at ||= Time.zone.now if record.respond_to?(:created_at)
      record.updated_at ||= Time.zone.now if record.respond_to?(:updated_at)
      record.save!
    end

    # Destroy a record that received a null payload. Override if you need
    # to do something other than a straight destroy (e.g. mark as archived).
    # @param record [ActiveRecord::Base]
    def destroy_record(record)
      record&.destroy
    end

    # Override this method (with `super`) if you want to add/change the default
    # attributes set to the new/existing record.
    # @param payload [Hash]
    def record_attributes(payload)
      klass = self.class.config[:record_class]
      attributes = {}
      schema = self.class.decoder.avro_schema
      schema.fields.each do |field|
        column = klass.columns.find { |c| c.name == field.name }
        next if column.nil?
        next if %w(updated_at created_at).include?(field.name)

        attributes[field.name] = _coerce_field(field, column, payload[field.name])
      end
      attributes
    end

  private

    # @param field [Avro::Schema]
    # @param column [ActiveRecord::ConnectionAdapters::Column]
    # @param val [Object]
    def _coerce_field(field, column, val)
      return nil if val.nil?

      field_type = field.type.type.to_sym
      if field_type == :union
        union_types = field.type.schemas.map { |s| s.type.to_sym }
        field_type = union_types.find { |t| t != :null }
      end
      if column.type == :datetime && %i(int long).include?(field_type)
        return Time.zone.strptime(val.to_s, '%s')
      end

      val
    end
  end
end
