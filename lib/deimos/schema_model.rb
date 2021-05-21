# frozen_string_literal: true

require 'json'

module Deimos
  # Base Class of Record Classes generated from Avro.
  class SchemaModel

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
      namespace + '.' + schema
    end

    # @return [Array<String>] an array of fields names in the schema.
    def schema_fields
      @validator.schema_fields.map do |field|
        field.name
      end
    end

    # TODO: Look into implementing these?

    # @return [String] the payload as a JSON string
    def to_json
      to_h.to_json
    end

    # Returns a Hash that can be used as the JSON representation for this object
    # @return [Hash] the payload as a hash.
    def as_json
      to_h.with_indifferent_access
    end

    # Converts the object to a hash which can be used in Kafka.
    # @return [Hash] the payload as a hash.
    def as_hash
      JSON.parse(to_json).with_indifferent_access
    end

    # @return [Hash] the payload as a hash.
    def to_h
      raise NotImplementedError
    end

  end
end
