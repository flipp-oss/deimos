# frozen_string_literal: true

require_relative 'avro_base'
require_relative 'avro_validation'
require 'avro_turf/messaging'

module Deimos
  module SchemaBackends
    # Encode / decode using the Avro schema registry.
    class AvroSchemaRegistry < AvroBase
      # @override
      def decode_payload(payload, schema:)
        avro_turf_messaging.decode(payload.to_s, schema_name: schema)
      end

      # @override
      def encode_payload(payload, schema: nil, topic: nil)
        avro_turf_messaging.encode(payload, schema_name: schema, subject: topic || schema)
      end

    private

      # @return [AvroTurf::Messaging]
      def avro_turf_messaging
        @avro_turf_messaging ||= AvroTurf::Messaging.new(
          schema_store: @schema_store,
          registry_url: Deimos.config.schema.registry_url,
          schemas_path: Deimos.config.schema.path,
          user: Deimos.config.schema.user,
          password: Deimos.config.schema.password,
          namespace: @namespace,
          logger: Deimos.config.logger
        )
      end
    end
  end
end
