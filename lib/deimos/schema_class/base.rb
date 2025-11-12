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
        raise MissingImplementationError
      end

      # @param key [String,Symbol]
      # @param val [Object]
      # @return [void]
      def []=(key, val)
        self.send("#{key}=", val)
      end

      # @param other [SchemaClass::Base]
      # @return [Boolean]
      def ==(other)
        comparison = other
        if other.class == self.class
          comparison = other.as_json
        end

        comparison == self.as_json
      end

      alias_method :eql?, :==

      # @return [String]
      def inspect
        klass = self.class
        "#{klass}(#{self.as_json})"
      end

      # Initializes this class from a given value
      # @param value [Object]
      # @return [SchemaClass::Base]
      def self.initialize_from_value(_value)
        raise MissingImplementationError
      end

    protected

      # @return [Integer]
      def hash
        as_json.hash
      end
    end
  end
end
