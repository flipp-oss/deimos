# frozen_string_literal: true

require 'json'

module Deimos
  module SchemaClass
    # Base Class for Schema Classes generated from Avro.
    class Base

      # Converts the object to a string that represents a JSON object
      # @return [String] a JSON string
      def to_json(*_args)
        to_h.to_json
      end

      # Converts the object to a hash which can be used for debugging.
      # @return [Hash] a hash representation of the payload
      def as_json(_opts={})
        JSON.parse(to_json)
      end

      # Converts the object attributes to a hash which can be used for Kafka
      # @return [Hash] the payload as a hash.
      def to_h
        raise NotImplementedError
      end

      # :nodoc:
      def ==(other)
        comparison = other
        if other.class == self.class
          comparison = other.state
        end

        comparison == self.state
      end

      # :nodoc:
      def to_s
        klass = self.class
        "#{klass}(#{self.as_json.symbolize_keys.to_s[1..-2]})"
      end

      # Returns the string form of the object as if it were to be initialized
      # @return [String]
      def as_new_string
        klass = self.class
        "#{klass}.new(#{self.as_json.symbolize_keys.to_s[1..-2]})"
      end
    protected

      # :nodoc:
      def state
        as_json
      end

      # :nodoc:
      def hash
        state.hash
      end

    end
  end
end
