# frozen_string_literal: true

module Deimos
  # Represents a field in the schema.
  class SchemaField
    # @return [String]
    attr_accessor :name
    # @return [String]
    attr_accessor :type
    # @return [Array<String>]
    attr_accessor :enum_values
    # @return [Object]
    attr_accessor :default

    # @param name [String]
    # @param type [Object]
    # @param enum_values [Array<String>]
    # @param default [Object]
    def initialize(name, type, enum_values=[], default=:no_default)
      @name = name
      @type = type
      @enum_values = enum_values
      @default = default
    end
  end

  module SchemaBackends
    # Base class for encoding / decoding.
    class Base
      # @return [String]
      attr_accessor :schema
      # @return [String]
      attr_accessor :namespace
      # @return [String]
      attr_accessor :key_schema

      # @param schema [String,Symbol]
      # @param namespace [String]
      def initialize(schema:, namespace: nil)
        @schema = schema
        @namespace = namespace
      end

      # @return [String]
      def inspect
        "Type #{self.class.name.demodulize} Schema: #{@namespace}.#{@schema} Key schema: #{@key_schema}"
      end

      # @return [Boolean]
      def supports_key_schemas?
        false
      end

      # @return [Boolean]
      def supports_class_generation?
        false
      end

      # Encode a payload with a schema. Public method.
      # @param payload [Hash]
      # @param schema [String,Symbol]
      # @param topic [String]
      # @return [String]
      def encode(payload, schema: nil, topic: nil, is_key: false)
        validate(payload, schema: schema || @schema)
        subject = is_key ? "#{topic}-key" : "#{topic}-value"
        encode_payload(payload, schema: schema || @schema, subject: subject)
      end

      # Decode a payload with a schema. Public method.
      # @param payload [String]
      # @param schema [String,Symbol]
      # @return [Hash,nil]
      def decode(payload, schema: nil)
        return nil if payload.nil?

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
      # Note that the "mock" version should return
      # its own symbol when this is called, since it may be called multiple
      # times depending on the order of RSpec helpers.
      # @return [Symbol]
      def self.mock_backend
        :mock
      end

      # The content type to use when encoding / decoding requests over HTTP via ActionController.
      # @return [String]
      def self.content_type
        raise MissingImplementationError
      end

      # Converts your schema to String form for generated YARD docs.
      # To be defined by subclass.
      # @param schema [Object]
      # @return [String] A string representation of the Type
      def self.field_type(_schema)
        raise MissingImplementationError
      end

      # Encode a payload. To be defined by subclass.
      # @param payload [Hash]
      # @param schema [String,Symbol]
      # @param subject [String]
      # @return [String]
      def encode_payload(_payload, schema:, subject: nil)
        raise MissingImplementationError
      end

      # Decode a payload. To be defined by subclass.
      # @param payload [String]
      # @param schema [String,Symbol]
      # @return [Hash]
      def decode_payload(_payload, schema:)
        raise MissingImplementationError
      end

      # Validate that a payload matches the schema. To be defined by subclass.
      # @param payload [Hash]
      # @param schema [String,Symbol]
      # @return [void]
      def validate(_payload, schema:)
        raise MissingImplementationError
      end

      # List of field names belonging to the schema. To be defined by subclass.
      # @return [Array<SchemaField>]
      def schema_fields
        raise MissingImplementationError
      end

      # Given a value and a field definition (as defined by whatever the
      # underlying schema library is), coerce the given value to
      # the given field type.
      # @param field [SchemaField]
      # @param value [Object]
      # @return [Object]
      def coerce_field(_field, _value)
        raise MissingImplementationError
      end

      # Given a field definition, return the SQL type that might be used in
      # ActiveRecord table creation - e.g. for Avro, a `long` type would
      # return `:bigint`. There are also special values that need to be returned:
      # `:array`, `:map` and `:record`, for types representing those structures.
      # `:enum` is also recognized.
      # @param field [SchemaField]
      # @return [Symbol]
      def sql_type(_field)
        raise MissingImplementationError
      end

      # Generate a key schema from the given value schema and key ID. This
      # is used when encoding or decoding keys from an existing value schema.
      # @param field_name [Symbol]
      def generate_key_schema(_field_name)
        raise MissingImplementationError
      end

      # Encode a message key. To be defined by subclass.
      # @param key [String,Hash] the value to use as the key.
      # @param key_id [String,Symbol] the field name of the key.
      # @param topic [String]
      # @return [String]
      def encode_key(_key, _key_id, topic: nil)
        raise MissingImplementationError
      end

      # Decode a message key. To be defined by subclass.
      # @param payload [Hash] the message itself.
      # @param key_id [String,Symbol] the field in the message to decode.
      # @return [String]
      def decode_key(_payload, _key_id)
        raise MissingImplementationError
      end

      # Forcefully loads the schema into memory.
      # @return [Object] The schema that is of use.
      def load_schema
        raise MissingImplementationError
      end
    end
  end
end
