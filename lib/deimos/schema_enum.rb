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

    # @return [String] the payload as a JSON string
    def to_json(*_args)
      raise NotImplementedError
    end
  end
end
