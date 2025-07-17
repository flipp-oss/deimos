# frozen_string_literal: true

require_relative 'base'
require 'json'

module Deimos
  module SchemaClass
    # Base Class for Enum Classes generated from Avro.
    class Enum < Base

      # @return [String]
      attr_accessor :value

      # @param other [Deimos::SchemaClass::Enum]
      # @return [Boolean]
      def ==(other)
        other.is_a?(self.class) ? other.value == @value : other == @value
      end

      # @return [String]
      def to_s
        @value.to_s
      end

      # @param value [String]
      def initialize(value)
        @value = value
      end

      # Returns all the valid symbols for this enum.
      # @return [Array<String>]
      def symbols
        raise MissingImplementationError
      end

      # @return [String]
      def as_json(_opts={})
        @value
      end

      # @return [SchemaClass::Enum]
      def self.initialize_from_value(value, from_message: false)
        return nil if value.nil?

        value.is_a?(self) ? value : self.new(value)
      end
    end
  end
end
