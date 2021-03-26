# frozen_string_literal: true

require 'json'

module Deimos
  # base class of the schema class enums generated from the schema backend
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