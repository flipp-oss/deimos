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
        msg = proto_schema.msgclass.new(**payload)
        self.class.proto_turf.encode(msg, subject: topic)
      end

    private

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
