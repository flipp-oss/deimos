require 'deimos/schema_model_enum'

module Deimos
  # :nodoc:
  class GeneratedAnEnumEnum < SchemaModelEnum
    # @!attribute [rw] status
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
