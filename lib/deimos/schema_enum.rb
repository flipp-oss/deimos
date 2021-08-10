# frozen_string_literal: true

require 'json'

module Deimos
  # Base Class for Enum Classes generated from Avro.
  class SchemaEnum

    # Returns all the valid symbols for this enum.
    # @return [Array<String>]
    def symbols
      raise NotImplementedError
    end

    # Converts the object to a string that represents a JSON object
    # @return [String] a JSON string
    def to_json(*_args)
      raise NotImplementedError
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
