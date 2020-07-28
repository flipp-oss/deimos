# frozen_string_literal: true

module Deimos
  # Represents a field in the schema.
  class SchemaField
    attr_accessor :name, :type, :enum_values

    # @param name [String]
    # @param type [Object]
    # @param enum_values [Array<String>]
    def initialize(name, type, enum_values=[])
      @name = name
      @type = type
      @enum_values = enum_values
    end
  end

  module SchemaBackends
    # Base class for encoding / decoding.
    class Base
      attr_accessor :schema, :namespace, :key_schema

      # @param schema [String|Symbol]
      # @param namespace [String]
      def initialize(schema:, namespace: nil)
        @schema = schema
        @namespace = namespace
      end

      # Encode a payload with a schema. Public method.
      # @param payload [Hash]
      # @param schema [Symbol|String]
      # @param topic [String]
      # @return [String]
      def encode(payload, schema: nil, topic: nil)
        validate(payload, schema: schema || @schema)
        encode_payload(payload, schema: schema || @schema, topic: topic)
      end

      # Decode a payload with a schema. Public method.
      # @param payload [String]
      # @param schema [Symbol|String]
      # @return [Hash]
      def decode(payload, schema: nil)
        decode_payload(payload, schema: schema || @schema)
      end

      # Given a hash, coerce its types to our schema. To be defined by subclass.
      # @param payload [Hash]
      # @return [Hash]
      def coerce(payload)
        result = {}
        self.schema_fields.each do |field|
          name = field.name
          next unless payload.key?(name)

          val = payload[name]
          result[name] = coerce_field(field, val)
        end
        result.with_indifferent_access
      end

      # Indicate a class which should act as a mocked version of this backend.
      # This class should perform all validations but not actually do any
      # encoding.
      # Note that the "mock" version (e.g. avro_validation) should return
      # its own symbol when this is called, since it may be called multiple
      # times depending on the order of RSpec helpers.
      # @return [Symbol]
      def self.mock_backend
        :mock
      end

      # The content type to use when encoding / decoding requests over HTTP via ActionController.
      # @return [String]
      def self.content_type
        raise NotImplementedError
      end

      # Encode a payload. To be defined by subclass.
      # @param payload [Hash]
      # @param schema [Symbol|String]
      # @param topic [String]
      # @return [String]
      def encode_payload(_payload, schema:, topic: nil)
        raise NotImplementedError
      end

      # Decode a payload. To be defined by subclass.
      # @param payload [String]
      # @param schema [String|Symbol]
      # @return [Hash]
      def decode_payload(_payload, schema:)
        raise NotImplementedError
      end

      # Validate that a payload matches the schema. To be defined by subclass.
      # @param payload [Hash]
      # @param schema [String|Symbol]
      def validate(_payload, schema:)
        raise NotImplementedError
      end

      # List of field names belonging to the schema. To be defined by subclass.
      # @return [Array<SchemaField>]
      def schema_fields
        raise NotImplementedError
      end

      # Given a value and a field definition (as defined by whatever the
      # underlying schema library is), coerce the given value to
      # the given field type.
      # @param field [SchemaField]
      # @param value [Object]
      # @return [Object]
      def coerce_field(_field, _value)
        raise NotImplementedError
      end

      # Given a field definition, return the SQL type that might be used in
      # ActiveRecord table creation - e.g. for Avro, a `long` type would
      # return `:bigint`. There are also special values that need to be returned:
      # `:array`, `:map` and `:record`, for types representing those structures.
      # `:enum` is also recognized.
      # @param field [SchemaField]
      # @return [Symbol]
      def sql_type(field)
        raise NotImplementedError
      end

      # Encode a message key. To be defined by subclass.
      # @param key [String|Hash] the value to use as the key.
      # @param key_id [Symbol|String] the field name of the key.
      # @param topic [String]
      # @return [String]
      def encode_key(_key, _key_id, topic: nil)
        raise NotImplementedError
      end

      # Decode a message key. To be defined by subclass.
      # @param payload [Hash] the message itself.
      # @param key_id [Symbol|String] the field in the message to decode.
      # @return [String]
      def decode_key(_payload, _key_id)
        raise NotImplementedError
      end
    end
  end
end
