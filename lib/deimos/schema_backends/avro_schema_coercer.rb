# frozen_string_literal: true

require 'active_support/time'

module Deimos
  # Class to coerce values in a payload to match a schema.
  class AvroSchemaCoercer
    # @param schema [Avro::Schema]
    def initialize(schema)
      @schema = schema
    end

    # Coerce sub-records in a payload to match the schema.
    # @param type [Avro::Schema::UnionSchema]
    # @param val [Object]
    # @return [Object]
    def coerce_union(type, val)
      union_types = type.schemas.map { |s| s.type.to_sym }
      return nil if val.nil? && union_types.include?(:null)

      schema_type = type.schemas.find { |s| s.type.to_sym != :null }
      coerce_type(schema_type, val)
    end

    # Coerce sub-records in a payload to match the schema.
    # @param type [Avro::Schema::RecordSchema]
    # @param val [Object]
    # @return [Object]
    def coerce_record(type, val)
      record = val.map do |name, value|
        field = type.fields.find { |f| f.name == name }
        coerce_type(field.type, value)
      end
      val.keys.zip(record).to_h
    end

    # Coerce values in a payload to match the schema.
    # @param type [Avro::Schema]
    # @param val [Object]
    # @return [Object]
    def coerce_type(type, val)
      int_classes = [Time, ActiveSupport::TimeWithZone]
      field_type = type.type.to_sym

      case field_type
      when :int, :long
        if %w(timestamp-millis timestamp-micros).include?(type.logical_type)
          val
        elsif val.is_a?(Integer) ||
              _is_integer_string?(val) ||
              int_classes.any? { |klass| val.is_a?(klass) }
          val.to_i
        else
          val # this will fail
        end
      when :float, :double
        if val.is_a?(Numeric) || _is_float_string?(val)
          val.to_f
        else
          val # this will fail
        end
      when :string
        if val.respond_to?(:to_str)
          val.to_s
        elsif _is_to_s_defined?(val)
          val.to_s
        else
          val # this will fail
        end
      when :boolean
        !(val.nil? || val == false)
      when :union
        coerce_union(type, val)
      when :record
        coerce_record(type, val)
      else
        val
      end
    end

  private

    # @param val [String]
    # @return [Boolean]
    def _is_integer_string?(val)
      return false unless val.is_a?(String)

      begin
        true if Integer(val)
      rescue StandardError
        false
      end
    end

    # @param val [String]
    # @return [Boolean]
    def _is_float_string?(val)
      return false unless val.is_a?(String)

      begin
        true if Float(val)
      rescue StandardError
        false
      end
    end

    # @param val [Object]
    # @return [Boolean]
    def _is_to_s_defined?(val)
      return false if val.nil?

      Object.instance_method(:to_s).bind(val).call != val.to_s
    end
  end
end
