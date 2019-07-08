# frozen_string_literal: true

require 'avro_turf/messaging'
require 'deimos/avro_data_coder'

module Deimos
  # Service Object to decode Avro messages.
  class AvroDataEncoder < AvroDataCoder
    # @param payload [Hash]
    # @param schema [String]
    # @return [String]
    def encode_local(payload, schema: nil)
      schema ||= @schema
      Avro::SchemaValidator.validate!(avro_schema(schema), payload,
                                      recursive: true,
                                      fail_on_extra_fields: true)
      avro_turf.encode(payload, schema_name: schema, namespace: @namespace)
    rescue Avro::IO::AvroTypeError
      # throw a more detailed error
      value_schema = @schema_store.find(schema, @namespace)
      Avro::SchemaValidator.validate!(value_schema, payload)
    end

    # @param payload [Hash]
    # @param schema [String]
    # @param topic [String]
    # @return [String]
    def encode(payload, schema: nil, topic: nil)
      schema ||= @schema
      Avro::SchemaValidator.validate!(avro_schema(schema), payload,
                                      recursive: true,
                                      fail_on_extra_fields: true)
      avro_turf_messaging.encode(payload, schema_name: schema, subject: topic)
    rescue Avro::IO::AvroTypeError
      # throw a more detailed error
      schema = @schema_store.find(@schema, @namespace)
      Avro::SchemaValidator.validate!(schema, payload)
    end

    # @param key_id [Symbol|String]
    # @param key [Object]
    # @param topic [String]
    # @return [String] the encoded key.
    def encode_key(key_id, key, topic=nil)
      key_schema = _generate_key_schema(key_id)
      field_name = _field_name_from_schema(key_schema)
      payload = { field_name => key }
      encode(payload, schema: key_schema['name'], topic: topic)
    end
  end
end
