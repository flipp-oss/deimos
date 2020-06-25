# frozen_string_literal: true

module Deimos
  module ActiveRecordConsume
    # Convert a message with a schema to an ActiveRecord model
    class SchemaModelConverter
      # Create new converter
      # @param decoder [SchemaBackends::Base] Incoming message schema.
      # @param klass [ActiveRecord::Base] Model to map to.
      def initialize(decoder, klass)
        @decoder = decoder
        @klass = klass
      end

      # Convert a message from a decoded hash to a set of ActiveRecord
      # attributes. Attributes that don't exist in the model will be ignored.
      # @param payload [Hash] Decoded message payload.
      # @return [Hash] Model attributes.
      def convert(payload)
        attributes = {}
        @decoder.schema_fields.each do |field|
          column = @klass.columns.find { |c| c.name == field.name }
          next if column.nil?
          next if %w(updated_at created_at).include?(field.name)

          attributes[field.name] = _coerce_field(column, payload[field.name])
        end
        attributes
      end

    private

      # @param column [ActiveRecord::ConnectionAdapters::Column]
      # @param val [Object]
      def _coerce_field(column, val)
        return nil if val.nil?

        if column.type == :datetime
          int_val = begin
                      val.is_a?(Integer) ? val : (val.is_a?(String) && Integer(val))
                    rescue StandardError
                      nil
                    end

          return Time.zone.at(int_val) if int_val
        end

        val
      end
    end
  end
end
