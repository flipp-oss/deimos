# frozen_string_literal: true

require 'json'

module Deimos
  # base class of the schema classes generated from the schema backend.
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

    # @override
    def to_json(options={})
      to_h.to_json
    end

    # @override
    def as_json(options={})
      to_h
    end

    # Converts the object to a hash which can be used in Kafka.
    def as_hash
      JSON.parse(to_json)
    end

    private

    # @return [Object] the payload as a hash.
    def to_h
      raise NotImplementedError
    end

  end
end
