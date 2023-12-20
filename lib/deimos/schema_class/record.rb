# frozen_string_literal: true

require_relative 'base'
require 'json'

module Deimos
  module SchemaClass
    # Base Class of Record Classes generated from Avro.
    class Record < Base

      attr_accessor :tombstone_key

      # Converts the object attributes to a hash which can be used for Kafka
      # @return [Hash] the payload as a hash.
      def to_h
        if self.tombstone_key
          { payload_key: self.tombstone_key&.as_json }
        else
          self.as_json
        end
      end

      # Merge a hash or an identical schema object with this one and return a new object.
      # @param other_hash [Hash,Deimos::SchemaClass::Base]
      # @return [Deimos::SchemaClass::Base]
      def merge(other_hash)
        obj = self.class.new(**self.to_h.symbolize_keys)
        other_hash.to_h.each do |k, v|
          obj.send("#{k}=", v)
        end
        obj
      end

      # Element access method as if this Object were a hash
      # @param key[String,Symbol]
      # @return [Object] The value of the attribute if exists, nil otherwise
      def [](key)
        self.try(key.to_sym)
      end

      # @return [Deimos::SchemaClass::Record]
      def with_indifferent_access
        self
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

    end
  end
end
