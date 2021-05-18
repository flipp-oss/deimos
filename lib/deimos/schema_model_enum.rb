# frozen_string_literal: true

require 'json'

module Deimos
  # Base Class for Enum Classes generated from Avro.
  class SchemaModelEnum

    # Returns all the valid symbols for this enum.
    # @return [Array<String>]
    def symbols
      raise NotImplementedError
    end

    # @override
    def to_json(options={})
      raise NotImplementedError
    end

  end
end