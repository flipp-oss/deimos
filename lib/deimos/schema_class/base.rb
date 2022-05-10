# frozen_string_literal: true

require 'json'

module Deimos
  module SchemaClass
    # Base Class for Schema Classes generated from Avro.
    class Base

      # :nodoc:
      def initialize(*_args)
      end

      # Converts the object to a string that represents a JSON object
      # @return [String] a JSON string
      def to_json(*_args)
        to_h.to_json
      end

      # Converts the object to a hash which can be used for debugging or comparing objects.
      # @return [Hash] a hash representation of the payload
      def as_json(_opts={})
        JSON.parse(to_json)
      end

      # Converts the object attributes to a hash which can be used for Kafka
      # @return [Hash] the payload as a hash.
      def to_h
        raise NotImplementedError
      end

      # @param key [String|Symbol]
      # @param val [Object]
      def []=(key, val)
        self.send("#{key}=", val)
      end

      # Merge a hash or an identical schema object with this one and return a new object.
      # @param other_hash [Hash|SchemaClasses::Base]
      # @return [SchemaClasses::Base]
      def merge(other_hash)
        obj = self.class.new(**self.to_h.symbolize_keys)
        other_hash.to_h.each do |k, v|
          obj.send("#{k}=", v)
        end
        obj
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
      def to_s
        klass = self.class
        "#{klass}(#{self.as_json.symbolize_keys.to_s[1..-2]})"
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
