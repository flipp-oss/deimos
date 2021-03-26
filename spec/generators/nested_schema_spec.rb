# frozen_string_literal: true

require './spec/schema_classes/my_nested_schema_schema'
require './spec/schema_classes/my_nested_schema_my_nested_record_schema'

# For testing the generated class.
RSpec.describe Deimos::MyNestedSchemaSchema do

  describe 'class initialization' do

    it 'should initialize the class with a nil optional record' do
      klass = described_class.new(
        test_id: 'some_id',
        test_float: 4.56,
        test_array: ['one string', 'two string', 'three string', 'four'],
        some_nested_record: Deimos::MyNestedSchemaMyNestedRecordSchema.new(
          some_int: 4,
          some_float: 1.1,
          some_string: "a string!",
          some_optional_int: 15
        ),
        some_optional_record: nil
      )
      expect(klass).to be_instance_of(described_class)
    end

    it 'should initialize the class with the optional record' do
      klass = described_class.new(
        test_id: 'some_id',
        test_float: 4.56,
        test_array: ['one string', 'two string', 'three string', 'four'],
        some_nested_record: Deimos::MyNestedSchemaMyNestedRecordSchema.new(
          some_int: 4,
          some_float: 1.1,
          some_string: "a string!",
          some_optional_int: 15
        ),
        some_optional_record: Deimos::MyNestedSchemaMyNestedRecordSchema.new(
          some_int: 5,
          some_float: 1.2,
          some_string: "another one",
          some_optional_int: nil
        ),
      )
      expect(klass).to be_instance_of(described_class)
    end

  end

end
