# frozen_string_literal: true

require_relative 'avro_base'

module Deimos
  module SchemaBackends
    # Leave Ruby hashes as is but validate them against the schema.
    # Useful for unit tests.
    class AvroValidation < AvroBase
      # @override
      def decode_payload(payload, schema: nil)
        JSON.parse(payload)
      end

      # @override
      def encode_payload(payload, schema: nil, topic: nil)
        payload.with_indifferent_access.to_json
      end
    end
  end
end
