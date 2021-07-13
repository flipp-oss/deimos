# frozen_string_literal: true

require 'json'

module Deimos
  # Base Class of Record Classes generated from Avro.
  class SchemaRecord
    # :nodoc:
    def initialize
    end

    # Recursively initializes the SchemaRecord from a raw hash
    # @param _hash[Hash]
    # @return [Deimos::SchemaRecord]
    def self.initialize_from_hash(_hash)
      raise NotImplementedError
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

    # Returns the schema validator from the schema backend
    # @return [Deimos::SchemaBackends::Base]
    def validator
      Deimos.schema_backend(schema: schema, namespace: namespace)
    end

    # @return [Array<String>] an array of fields names in the schema.
    def schema_fields
      validator.schema_fields.map(&:name)
    end

    # Converts the object to a string that represents a JSON object
    # @return [String] a JSON
    def to_json(*_args)
      to_h.to_json
    end

    # Converts the object to a hash which can be used in Kafka.
    # @return [Hash] a hash representation of the payload
    def as_json(_opts={})
      JSON.parse(to_json)
    end

    # Converts the object attributes to a hash
    # TODO: Decide if this should do recursion to call class to_h's too
    # @return [Hash] the payload as a hash.
    def to_h
      raise NotImplementedError
    end
  end
end
