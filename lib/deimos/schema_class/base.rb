# frozen_string_literal: true

require 'json'

module Deimos
  module SchemaClass
    # Base Class for Schema Classes generated from Avro.
    class Base

      # @param _args [Array<Object>]
      def initialize(*_args)
      end

      # Converts the object to a hash which can be used for debugging or comparing objects.
      # @param _opts [Hash]
      # @return [Hash] a hash representation of the payload
      def as_json(_opts={})
        raise NotImplementedError
      end

      # @return [Hash]
      def to_h
        self.as_json
      end

      # @param key [String,Symbol]
      # @param val [Object]
      # @return [void]
      def []=(key, val)
        self.send("#{key}=", val)
      end

      # @param other [Deimos::SchemaClass::Base]
      # @return [Boolean]
      def ==(other)
        comparison = other
        if other.class == self.class
          comparison = other.as_json
        end

        comparison == self.as_json
      end

      # @return [String]
      def inspect
        klass = self.class
        "#{klass}(#{self.as_json})"
      end

      # Initializes this class from a given value
      # @param value [Object]
      # @return [Deimos::SchemaClass::Base]
      def self.initialize_from_value(value)
        raise NotImplementedError
      end

    protected

      # @return [Integer]
      def hash
        as_json.hash
      end
    end
  end
end
