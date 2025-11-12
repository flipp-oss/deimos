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

      schema_type = find_schema_type(type, val)
      coerce_type(schema_type, val)
    end

    # Find the right schema for val from a UnionSchema.
    # @param type [Avro::Schema::UnionSchema]
    # @param val [Object]
    # @return [Avro::Schema::PrimitiveSchema]
    def find_schema_type(type, val)
      int_classes = [Time, ActiveSupport::TimeWithZone]

      schema_type = type.schemas.find do |schema|
        field_type = schema.type.to_sym

        case field_type
        when :int, :long
          val.is_a?(Integer) ||
            _is_integer_string?(val) ||
            int_classes.any? { |klass| val.is_a?(klass) }
        when :float, :double
          val.is_a?(Numeric) || _is_float_string?(val)
        when :array
          val.is_a?(Array)
        when :record
          if val.is_a?(Hash)
            schema_fields_set = Set.new(schema.fields.map(&:name))
            Set.new(val.keys).subset?(schema_fields_set)
          else
            # If the value is not a hash, we can't coerce it to a record.
            # Keep looking for another schema
            false
          end
        else
          schema.type.to_sym != :null
        end
      end

      raise "No Schema type found for VALUE: #{val}\n TYPE: #{type}" if schema_type.nil?

      schema_type
    end

    # Coerce sub-records in a payload to match the schema.
    # @param type [Avro::Schema::RecordSchema]
    # @param val [Object]
    # @return [Object]
    def coerce_record(type, val)
      return nil if val.nil?

      record = val.map do |name, value|
        field = type.fields.find { |f| f.name == name }
        coerce_type(field.type, value)
      end
      val.keys.zip(record).to_h
    end

    # @param type [Avro::Schema::RecordSchema]
    # @param val [Object]
    # @return [Integer]
    def coerce_int(type, val)
      int_classes = [Time, ActiveSupport::TimeWithZone]
      if %w(timestamp-millis timestamp-micros).include?(type.logical_type)
        val
      elsif val.is_a?(Integer) ||
            _is_integer_string?(val) ||
            int_classes.any? { |klass| val.is_a?(klass) }
        val.to_i
      else # rubocop:disable Lint/DuplicateBranch
        val # this will fail
      end
    end

    # @param val [Object]
    # @return [Float]
    def coerce_float(val)
      if val.is_a?(Numeric) || _is_float_string?(val)
        val.to_f
      else
        val # this will fail
      end
    end

    # @param val [Object]
    # @return [String]
    def coerce_string(val)
      if val.respond_to?(:to_str) || _is_to_s_defined?(val)
        val.to_s
      else
        val # this will fail
      end
    end

    # @param val [Object]
    # @return [Boolean]
    def coerce_boolean(val) # rubocop:disable Naming/PredicateMethod
      !(val.nil? || val == false)
    end

    # Coerce values in a payload to match the schema.
    # @param type [Avro::Schema]
    # @param val [Object]
    # @return [Object]
    def coerce_type(type, val)
      field_type = type.type.to_sym

      case field_type
      when :int, :long
        coerce_int(type, val)
      when :float, :double
        coerce_float(val)
      when :string
        coerce_string(val)
      when :boolean
        coerce_boolean(val)
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
