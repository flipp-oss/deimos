# frozen_string_literal: true

module Deimos
  # :nodoc:
  class AnEnum < SchemaEnum
    # @return ['sym1', 'sym2']
    attr_accessor :an_enum

    # :nodoc:
    def initialize(an_enum:)
      @an_enum = an_enum
    end

    # @override
    def symbols
      %w(sym1 sym2)
    end

    # @override
    def as_json(options={})
      @an_enum
    end

  end
end
