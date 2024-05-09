# frozen_string_literal: true

module Deimos
  module SchemaBackends
    # Schema backend that passes through as a basic string.
    class Plain < Base

      # @override
      def generate_key_schema(field_name)
      end

      # @override
      def decode_payload(payload, schema:)
        payload
      end

      # @override
      def encode_payload(payload, schema:, topic: nil)
        payload
      end

      # @override
      def validate(payload, schema:)
      end

      # @override
      def schema_fields
        []
      end

      # @override
      def coerce_field(_field, value)
        value
      end

      # @override
      def encode_key(key_id, key, topic: nil)
        key
      end

      # @override
      def decode_key(payload, key_id)
        payload[key_id]
      end
    end
  end
end
