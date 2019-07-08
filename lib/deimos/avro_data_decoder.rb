# frozen_string_literal: true

require 'avro_turf/messaging'
require 'deimos/avro_data_coder'

module Deimos
  # Service Object to decode avro messages
  class AvroDataDecoder < AvroDataCoder
    # Decode some data.
    # @param payload [Hash|String]
    # @param schema [String]
    # @return [Hash]
    def decode(payload, schema: nil)
      schema ||= @schema
      avro_turf_messaging.decode(payload, schema_name: schema)
    end

    # Decode against a local schema.
    # @param payload [Hash]
    # @param schema [String]
    # @return [Hash]
    def decode_local(payload, schema: nil)
      schema ||= @schema
      avro_turf.decode(payload, schema_name: schema, namespace: @namespace)
    end

    # @param payload [String] the encoded key.
    # @param key_id [String|Symbol]
    # @return [Object] the decoded key (int/long/string).
    def decode_key(payload, key_id)
      key_schema = _generate_key_schema(key_id)
      field_name = _field_name_from_schema(key_schema)
      decode(payload, schema: key_schema['name'])[field_name]
    end
  end
end
