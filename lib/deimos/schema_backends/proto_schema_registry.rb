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
      def encode_payload(payload, schema: nil, topic: nil)
        msg = payload.is_a?(Hash) ? proto_schema.msgclass.new(**payload) : payload
        self.class.proto_turf.encode(msg, subject: topic)
      end

      # @return [ProtoTurf]
      def self.proto_turf
        @proto_turf ||= ProtoTurf.new(
          registry_url: Deimos.config.schema.registry_url,
          logger: Karafka.logger
        )
      end
    end
  end
end
