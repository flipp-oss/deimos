# frozen_string_literal: true

require_relative 'avro_base'

module Deimos
  module SchemaBackends
    # Encode / decode using local Avro encoding.
    class AvroLocal < AvroBase
      # @override
      def decode_payload(payload, schema:)
        avro_turf.decode(payload, schema_name: schema, namespace: @namespace)
      end

      # @override
      def encode_payload(payload, schema: nil, topic: nil)
        avro_turf.encode(payload, schema_name: schema, namespace: @namespace)
      end

    private

      # @return [AvroTurf]
      def avro_turf
        path = Deimos.config.schema.path.presence || Deimos.config.schema.paths[:avro].first
        if path.blank?
          raise "No schema paths configured for `avro` backend!"
        end
        @avro_turf ||= AvroTurf.new(
          schemas_path: path,
          schema_store: @schema_store
        )
      end
    end
  end
end
