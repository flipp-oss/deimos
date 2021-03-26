module Deimos
  # :nodoc:
  class GeneratedARecordSchema < SchemaModel
    # @!attribute [rw] status
    # @return [String]
    attr_accessor :a_record_field

    # @override
    def initialize(a_record_field:)
      super()
      @a_record_field = a_record_field
    end

    # @override
    def schema
      'Generated'
    end

    # @override
    def namespace
      'com.my-namespace'
    end

    # @override
    def to_h
      {
        'a_record_field' => @a_record_field,
      }
    end

  end
end
