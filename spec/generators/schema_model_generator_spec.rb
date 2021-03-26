# frozen_string_literal: true

require 'generators/deimos/schema_model_generator'

RSpec.describe Deimos::Generators::SchemaModelGenerator do
  after(:each) do
    FileUtils.rm_rf('app') if File.exist?('app')
  end

  it 'should generate a schema model class' do
    described_class.start(['com.my-namespace.Generated'])
    files = Dir['app/lib/schema_models/com/my-namespace/*.rb']
    expect(files.length).to eq(3)
    results = <<~CLASS
module Deimos
  # :nodoc:
  class GeneratedSchema < SchemaModel
    # @!attribute [rw] status
    # @return [String]
    attr_accessor :a_string
    # @!attribute [rw] status
    # @return [Integer]
    attr_accessor :a_int
    # @!attribute [rw] status
    # @return [Integer]
    attr_accessor :a_long
    # @!attribute [rw] status
    # @return [Float]
    attr_accessor :a_float
    # @!attribute [rw] status
    # @return [Float]
    attr_accessor :a_double
    # @!attribute [rw] status
    # @return [Deimos::GeneratedAnEnumEnum]
    attr_accessor :an_enum
    # @!attribute [rw] status
    # @return [Array<Integer>]
    attr_accessor :an_array
    # @!attribute [rw] status
    # @return [Hash<String, String>]
    attr_accessor :a_map
    # @!attribute [rw] status
    # @return [String]
    attr_accessor :timestamp
    # @!attribute [rw] status
    # @return [String]
    attr_accessor :message_id
    # @!attribute [rw] status
    # @return [Deimos::GeneratedARecordSchema]
    attr_accessor :a_record

    # @override
    def initialize(a_string:, a_int:, a_long:, a_float:, a_double:, an_enum:, an_array:, a_map:, timestamp:, message_id:, a_record:)
      super()
      @a_string = a_string
      @a_int = a_int
      @a_long = a_long
      @a_float = a_float
      @a_double = a_double
      @an_enum = an_enum
      @an_array = an_array
      @a_map = a_map
      @timestamp = timestamp
      @message_id = message_id
      @a_record = a_record
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
        'a_string' => @a_string,
        'a_int' => @a_int,
        'a_long' => @a_long,
        'a_float' => @a_float,
        'a_double' => @a_double,
        'an_enum' => @an_enum,
        'an_array' => @an_array,
        'a_map' => @a_map,
        'timestamp' => @timestamp,
        'message_id' => @message_id,
        'a_record' => @a_record,
      }
    end

  end
end
    CLASS
    expect(File.read(files[0])).to eq(results)
    results = <<~RECORD
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
    RECORD
    expect(File.read(files[1])).to eq(results)
    results = <<~ENUM
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
    ENUM
    expect(File.read(files[2])).to eq(results)
  end

  it 'should generate a nested schema model class' do
    described_class.start(['com.my-namespace.MyNestedSchema'])
    files = Dir['app/lib/schema_models/com/my-namespace/*.rb']
    expect(files.length).to eq(2)
    results = <<~CLASS
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
    CLASS
    expect(File.read(files[1])).to eq(results)
  end

  it 'should generate all the schema model classes in schema.path' do
    described_class.start([])
    my_namespace_files = Dir['app/lib/schema_models/com/my-namespace/*.rb']
    request_files = Dir['app/lib/schema_models/com/my-namespace/request/*.rb']
    response_files = Dir['app/lib/schema_models/com/my-namespace/response/*.rb']
    expect(my_namespace_files.length).to eq(15)
    expect(request_files.length).to eq(3)
    expect(response_files.length).to eq(3)
  end

end
