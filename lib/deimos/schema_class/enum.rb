# frozen_string_literal: true

require_relative 'base'
require 'json'

module Deimos
  module SchemaClass
    # Base Class for Enum Classes generated from Avro.
    class Enum < Base
      # Returns all the valid symbols for this enum.
      # @return [Array<String>]
      def symbols
        raise NotImplementedError
      end
    end
  end
end
