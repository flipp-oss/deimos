# frozen_string_literal: true

require_relative 'avro_base'

module Deimos
  module SchemaBackends
    # Encode / decode using the Avro schema registry.
    class AvroSchemaRegistry < AvroBase
      # @override
      def decode_payload(payload, schema:)
        schema_registry.decode(payload.to_s)
      end

      # @override
      def encode_payload(payload, schema: nil, subject: nil)
        schema_registry.encode(payload, subject: subject || schema, schema_name: "#{@namespace}.#{schema}")
      end

    private

      # @return [SchemaRegistry::Client]
      def schema_registry
        @schema_registry ||= SchemaRegistry::Client.new(
          registry_url: @registry_info&.url || Deimos.config.schema.registry_url,
          logger: Karafka.logger,
          user: @registry_info&.user || Deimos.config.schema.user,
          password: @registry_info&.password || Deimos.config.schema.password,
          schema_type: SchemaRegistry::Schema::Avro.new(schema_store: @schema_store)
        )
      end
    end
  end
end
