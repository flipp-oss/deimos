# frozen_string_literal: true

require_relative 'proto_base'
require 'schema_registry_client'

module Deimos
  module SchemaBackends
    # Encode / decode using the Protobuf schema registry.
    class ProtoSchemaRegistry < ProtoBase

      # @override
      def decode_payload(payload, schema:)
        self.class.schema_registry.decode(payload)
      end

      # @override
      def encode_payload(payload, schema: nil, subject: nil)
        msg = payload.is_a?(Hash) ? proto_schema.msgclass.new(**payload) : payload
        encoder = subject&.ends_with?('-key') ? self.class.key_schema_registry : self.class.schema_registry
        encoder.encode(msg, subject: subject)
      end

      # @override
      def encode_proto_key(key, topic: nil, field: nil)
        schema_text = SchemaRegistry::Output::JsonSchema.output(proto_schema.to_proto, path: field)
        self.class.key_schema_registry.encode(key, subject: "#{topic}-key", schema_text: schema_text)
      end

      # @override
      def decode_proto_key(payload)
        self.class.key_schema_registry.decode(payload)
      end

      # @return [ProtoTurf]
      def self.schema_registry
        @schema_registry ||= ProtoTurf.new(
          registry_url: Deimos.config.schema.registry_url,
          logger: Karafka.logger
        )
      end

      def self.key_schema_registry
        @key_schema_registry ||= SchemaRegistry::Client.new(
          registry_url: Deimos.config.schema.registry_url,
          logger: Karafka.logger,
          schema_type: SchemaRegistry::Schema::ProtoJsonSchema
        )
      end

    end
  end
end
