# frozen_string_literal: true

module Deimos
  # :nodoc:
  class AnEnum < SchemaEnum
    # @return ['sym1', 'sym2']
    attr_accessor :an_enum

    # :nodoc:
    def initialize(an_enum:)
      super()
      @an_enum = an_enum
    end

    # :nodoc:
    def self.initialize_from_value(value)
      self.new(an_enum: value)
    end

    # @override
    def symbols
      %w(sym1 sym2)
    end

    # @override
    def as_json(_options={})
      @an_enum
    end
  end
end
