# frozen_string_literal: true

require 'json'

module Deimos
  module SchemaClass
    # Base Class for Schema Classes generated from Avro.
    class Base
      # :nodoc:
      def initialize(*_args)
      end

      # Converts the object to a hash which can be used for debugging or comparing objects.
      # @return [Hash] a hash representation of the payload
      def as_json(_opts={})
        raise NotImplementedError
      end

      # @param key [String|Symbol]
      # @param val [Object]
      def []=(key, val)
        self.send("#{key}=", val)
      end

      # :nodoc:
      def ==(other)
        comparison = other
        if other.class == self.class
          comparison = other.as_json
        end

        comparison == self.as_json
      end

      # :nodoc:
      def inspect
        klass = self.class
        "#{klass}(#{self.as_json})"
      end

      # Initializes this class from a given value
      # @param value [Object]
      def self.initialize_from_value(value)
        raise NotImplementedError
      end

    protected

      # :nodoc:
      def hash
        as_json.hash
      end
    end
  end
end
