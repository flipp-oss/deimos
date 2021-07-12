# frozen_string_literal: true

require 'generators/deimos/schema_class_generator'

RSpec.describe Deimos::Generators::SchemaClassGenerator do
  let(:schema_class_path) { 'app/lib/schema_classes/com/my-namespace' }

  before(:each) do
    Deimos.configure do
      schema.generated_class_path('app/lib/schema_classes')
    end
  end

  after(:each) do
    FileUtils.rm_rf(schema_class_path) if File.exist?(schema_class_path)
  end

  describe 'A Schema' do
    let(:generated_class) do
      <<~CLASS
        # frozen_string_literal: true

        module Deimos
          # :nodoc:
          class Generated < SchemaRecord
            # @return [String]
            attr_accessor :a_string
            # @return [Integer]
            attr_accessor :a_int
            # @return [Integer]
            attr_accessor :a_long
            # @return [Float]
            attr_accessor :a_float
            # @return [Float]
            attr_accessor :a_double
            # @return [nil, Integer]
            attr_accessor :an_optional_int
            # @return [Deimos::AnEnum]
            attr_accessor :an_enum
            # @return [Array<Integer>]
            attr_accessor :an_array
            # @return [Hash<String, String>]
            attr_accessor :a_map
            # @return [String]
            attr_accessor :timestamp
            # @return [String]
            attr_accessor :message_id
            # @return [Deimos::ARecord]
            attr_accessor :a_record
        
            # @override
            def initialize(a_string:, a_int:, a_long:, a_float:, a_double:, an_optional_int:, an_enum:, an_array:, a_map:, timestamp:, message_id:, a_record:)
              super()
              @a_string = a_string
              @a_int = a_int
              @a_long = a_long
              @a_float = a_float
              @a_double = a_double
              @an_optional_int = an_optional_int
              @an_enum = an_enum
              @an_array = an_array
              @a_map = a_map
              @timestamp = timestamp
              @message_id = message_id
              @a_record = a_record
            end
        
            # @override
            def self.initialize_from_hash(hash)
              return unless hash.any?

              payload = {}
              hash.each do |key, value|
                payload[key.to_sym] = case key.to_sym
                                      when :an_enum
                                        Deimos::AnEnum.initialize_from_value(value)
                                      when :a_record
                                        Deimos::ARecord.initialize_from_hash(value)
                                      else
                                        value
                                      end
              end
              self.new(payload)
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
                'an_optional_int' => @an_optional_int,
                'an_enum' => @an_enum,
                'an_array' => @an_array,
                'a_map' => @a_map,
                'timestamp' => @timestamp,
                'message_id' => @message_id,
                'a_record' => @a_record
              }
            end
          end
        end
      CLASS
    end
    let(:a_record) do
      <<~RECORD
        # frozen_string_literal: true

        module Deimos
          # :nodoc:
          class ARecord < SchemaRecord
            # @return [String]
            attr_accessor :a_record_field
        
            # @override
            def initialize(a_record_field:)
              super()
              @a_record_field = a_record_field
            end
        
            # @override
            def self.initialize_from_hash(hash)
              return unless hash.any?

              payload = {}
              hash.each do |key, value|
                payload[key.to_sym] = value
              end
              self.new(payload)
            end
        
            # @override
            def schema
              'ARecord'
            end
        
            # @override
            def namespace
              'com.my-namespace'
            end
        
            # @override
            def to_h
              {
                'a_record_field' => @a_record_field
              }
            end
          end
        end
      RECORD
    end
    let(:an_enum) do
      <<~ENUM
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
              self.new(@an_enum: value)
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
      ENUM
    end
    let(:files) { Dir["#{schema_class_path}/*.rb"] }

    before(:each) do
      described_class.start(['com.my-namespace.Generated'])
    end

    it 'should generate the correct number of classes' do
      expect(files.length).to eq(3)
    end

    it 'should generate a schema class' do
      generated_path = files.select { |f| f =~ /generated/ }.first
      expect(File.read(generated_path)).to eq(generated_class)
    end

    it 'should generate a class for a_record' do
      a_record_path = files.select { |f| f =~ /a_record/ }.first
      expect(File.read(a_record_path)).to eq(a_record)
    end

    it 'should generate a class for an_enum' do
      an_enum_path = files.select { |f| f =~ /an_enum/ }.first
      expect(File.read(an_enum_path)).to eq(an_enum)
    end
  end

  describe 'A Nested Schema' do
    let(:my_nested_schema) do
      <<~CLASS
        # frozen_string_literal: true

        module Deimos
          # :nodoc:
          class MyNestedSchema < SchemaRecord
            # @return [String]
            attr_accessor :test_id
            # @return [Float]
            attr_accessor :test_float
            # @return [Array<String>]
            attr_accessor :test_array
            # @return [Deimos::MyNestedRecord]
            attr_accessor :some_nested_record
            # @return [nil, Deimos::MyNestedRecord]
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
            def self.initialize_from_hash(hash)
              return unless hash.any?

              payload = {}
              hash.each do |key, value|
                payload[key.to_sym] = case key.to_sym
                                      when :some_nested_record, :some_optional_record
                                        Deimos::MyNestedRecord.initialize_from_hash(value)
                                      else
                                        value
                                      end
              end
              self.new(payload)
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
                'some_optional_record' => @some_optional_record
              }
            end
          end
        end
      CLASS
    end
    let(:my_nested_record) do
      <<~CLASS
        # frozen_string_literal: true
        
        module Deimos
          # :nodoc:
          class MyNestedRecord < SchemaRecord
            # @return [Integer]
            attr_accessor :some_int
            # @return [Float]
            attr_accessor :some_float
            # @return [String]
            attr_accessor :some_string
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
            def self.initialize_from_hash(hash)
              return unless hash.any?

              payload = {}
              hash.each do |key, value|
                payload[key.to_sym] = value
              end
              self.new(payload)
            end

            # @override
            def schema
              'MyNestedRecord'
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
                'some_optional_int' => @some_optional_int
              }
            end
          end
        end
      CLASS
    end
    let(:files) { Dir["#{schema_class_path}/*.rb"] }

    before(:each) do
      described_class.start(['com.my-namespace.MyNestedSchema'])
    end

    it 'should generate the correct number of classes' do
      expect(files.length).to eq(2)
    end

    it 'should generate a nested schema class' do
      my_nested_schema_path = files.select { |f| f =~ /my_nested_schema/ }.first
      expect(File.read(my_nested_schema_path)).to eq(my_nested_schema)
    end

    it 'should generate a class for my_nested_record' do
      my_nested_record_path = files.select { |f| f =~ /my_nested_record/ }.first
      expect(File.read(my_nested_record_path)).to eq(my_nested_record)
    end
  end

  it 'should generate all the schema model classes in schema.path' do
    described_class.start([])
    my_namespace_files = Dir['app/lib/schema_classes/com/my-namespace/*.rb']
    request_files = Dir['app/lib/schema_classes/com/my-namespace/request/*.rb']
    response_files = Dir['app/lib/schema_classes/com/my-namespace/response/*.rb']
    expect(my_namespace_files.length).to eq(15)
    expect(request_files.length).to eq(3)
    expect(response_files.length).to eq(3)
  end

end
