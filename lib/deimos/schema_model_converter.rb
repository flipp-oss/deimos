# frozen_string_literal: true

module Deimos
  # Convert a message with an Avro Schema to an ActiveRecord model
  class SchemaModelConverter
    # Create new converter
    # @param schema [Avro::Schema] Incoming message schema.
    # @param klass [ActiveRecord::Base] Model to map to.
    def initialize(schema, klass)
      @schema = schema
      @klass = klass
    end

    # Convert a message from a decoded Avro hash to a set of ActiveRecord
    # attributes. Attributes that don't exist in the model will be ignored.
    # @param payload [Hash] Decoded message payload.
    # @return [Hash] Model attributes.
    def convert(payload)
      attributes = {}
      @schema.fields.each do |field|
        column = @klass.columns.find { |c| c.name == field.name }
        next if column.nil?

        # Ignore ActiveRecord timestamps
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
