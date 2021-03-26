module Deimos
  # :nodoc:
  class MyNestedSchemaMyNestedRecordSchema < SchemaModel
    # @!attribute [rw] status
    # @return [Integer]
    attr_accessor :some_int
    # @!attribute [rw] status
    # @return [Float]
    attr_accessor :some_float
    # @!attribute [rw] status
    # @return [String]
    attr_accessor :some_string
    # @!attribute [rw] status
    # @return [nil, Integer]
    attr_accessor :some_optional_int

    # @override
    def initialize(some_int:, some_float:, some_string:, some_optional_int:)
      super()
      @some_int = some_int
      @some_float = some_float
      @some_string = some_string
      @some_optional_int = some_optional_int
    end

    # @override
    def schema
      'MyNestedSchema'
    end

    # @override
    def namespace
      'com.my-namespace'
    end

    # @override
    def to_h
      {
        'some_int' => @some_int,
        'some_float' => @some_float,
        'some_string' => @some_string,
        'some_optional_int' => @some_optional_int,
      }
    end

  end
end
