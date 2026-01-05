# frozen_string_literal: true

require_relative 'proto_base'
require 'schema_registry_client'

module Deimos
  module SchemaBackends
    # Encode / decode using a local protobuf object.
    class ProtoLocal < ProtoBase

      # @override
      def decode_payload(payload, schema:)
        proto_schema.msgclass.decode(payload)
      end

      # @override
      def encode_payload(payload, schema: nil, subject: nil)
        msg = payload.is_a?(Hash) ? proto_schema.msgclass.new(**payload) : payload
        proto_schema.msgclass.encode(msg)
      end

      # @return [SchemaRegistry::Client]
      def self.schema_registry
        @schema_registry ||= SchemaRegistry::Client.new(
          registry_url: Deimos.config.schema.registry_url,
          logger: Karafka.logger
        )
      end
    end
  end
end
