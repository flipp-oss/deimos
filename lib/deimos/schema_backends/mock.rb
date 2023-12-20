# frozen_string_literal: true

module Deimos
  module SchemaBackends
    # Mock implementation of a schema backend that does no encoding or validation.
    class Mock < Base
      # @override
      def decode_payload(payload, schema:)
        payload.is_a?(String) ? 'payload-decoded' : payload.map { |k, v| [k, "decoded-#{v}"] }
      end

      # @override
      def encode_payload(payload, schema:, topic: nil)
        payload.is_a?(String) ? 'payload-encoded' : payload.map { |k, v| [k, "encoded-#{v}"] }
      end

      # @override
      def validate(payload, schema:)
      end

      # @override
      def schema_fields
        []
      end

      # @param _field [Deimos::SchemaField]
      # @param value [Object]
      # @override
      def coerce_field(_field, value)
        value
      end

      # @override
      def encode_key(key_id, key, topic: nil)
        { key_id => key }
      end

      # @override
      def decode_key(payload, key_id)
        payload[key_id]
      end
    end
  end
end
