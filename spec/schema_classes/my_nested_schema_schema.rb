module Deimos
  # :nodoc:
  class MyNestedSchemaSchema < SchemaModel
    # @!attribute [rw] status
    # @return [String]
    attr_accessor :test_id
    # @!attribute [rw] status
    # @return [Float]
    attr_accessor :test_float
    # @!attribute [rw] status
    # @return [Array<String>]
    attr_accessor :test_array
    # @!attribute [rw] status
    # @return [Deimos::MyNestedSchemaMyNestedRecordSchema]
    attr_accessor :some_nested_record
    # @!attribute [rw] status
    # @return [nil, Deimos::MyNestedSchemaMyNestedRecordSchema]
    attr_accessor :some_optional_record

    # @override
    def initialize(test_id:, test_float:, test_array:, some_nested_record:, some_optional_record:)
      super()
      @test_id = test_id
      @test_float = test_float
      @test_array = test_array
      @some_nested_record = some_nested_record
      @some_optional_record = some_optional_record
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
        'test_id' => @test_id,
        'test_float' => @test_float,
        'test_array' => @test_array,
        'some_nested_record' => @some_nested_record,
        'some_optional_record' => @some_optional_record,
      }
    end

  end
end
