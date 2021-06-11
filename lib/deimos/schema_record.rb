# frozen_string_literal: true

require 'json'

module Deimos
  # Base Class of Record Classes generated from Avro.
  class SchemaRecord
    # :nodoc:
    def initialize
      @validator = Deimos.schema_backend(schema: schema, namespace: namespace)
    end

    # Returns the schema name of the inheriting class.
    # @return [String]
    def schema
      raise NotImplementedError
    end

    # Returns the namespace for the schema of the inheriting class.
    # @return [String]
    def namespace
      raise NotImplementedError
    end

    # Returns the full schema name of the inheriting class.
    # @return [String]
    def full_schema
      "#{namespace}.#{schema}"
    end

    # @return [Array<String>] an array of fields names in the schema.
    def schema_fields
      @validator.schema_fields.map(&:name)
    end

    # @override
    def to_json
      to_h.to_json
    end

    # @override
    def as_json(opts={})
      to_h
    end

    # Converts the object to a hash which can be used in Kafka.
    # @return [Hash] the payload as a hash.
    # TODO: Figure out if this is the best way to convert this to a usable hash... seems kind of silly to take the Hash
    # and convert it to JSON string, and parse it again.. I guess it covers the objects inside of it and converts them properly
    def as_hash
      JSON.parse(to_json)
    end

    private # TODO: Look into why this is needed

    # @return [Hash] the payload as a hash.
    def to_h
      raise NotImplementedError
    end
  end
end
