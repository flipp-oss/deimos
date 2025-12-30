# frozen_string_literal: true

require_relative 'proto_base'
require 'proto_turf'

module Deimos
  module SchemaBackends
    # Encode / decode using the Protobuf schema registry.
    class ProtoSchemaRegistry < ProtoBase

      # @override
      def decode_payload(payload, schema:)
        self.class.proto_turf.decode(payload)
      end

      # @override
      def encode_payload(payload, schema: nil, subject: nil)
        msg = payload.is_a?(Hash) ? proto_schema.msgclass.new(**payload) : payload
        encoder = subject&.ends_with?('-key') ? self.class.key_proto_turf : self.class.proto_turf
        encoder.encode(msg, subject: subject)
      end

      # @override
      def encode_proto_key(key, topic: nil, field: nil)
        schema_text = ProtoTurf::Output::JsonSchema.output(proto_schema.to_proto, path: field)
        self.class.key_proto_turf.encode(key, subject: "#{topic}-key", schema_text: schema_text)
      end

      # @override
      def decode_proto_key(payload)
        self.class.key_proto_turf.decode(payload)
      end

      # @return [ProtoTurf]
      def self.proto_turf
        @proto_turf ||= ProtoTurf.new(
          registry_url: Deimos.config.schema.registry_url,
          logger: Karafka.logger
        )
      end

      def self.key_proto_turf
        @key_proto_turf ||= ProtoTurf.new(
          registry_url: Deimos.config.schema.registry_url,
          logger: Karafka.logger,
          schema_type: 'JSON')
      end

    end
  end
end
