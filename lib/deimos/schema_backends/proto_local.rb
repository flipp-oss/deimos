# frozen_string_literal: true

require_relative 'proto_base'
require 'proto_turf'

module Deimos
  module SchemaBackends
    # Encode / decode using a local protobuf object.
    class ProtoLocal < ProtoBase

      # @override
      def decode_payload(payload, schema:)
        proto_schema.msgclass.decode(payload)
      end

      # @override
      def encode_payload(payload, schema: nil, topic: nil)
        msg = payload.is_a?(Hash) ? proto_schema.msgclass.new(**payload) : payload
        proto_schema.msgclass.encode(msg)
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
