# frozen_string_literal: true

require './spec/schema_classes/generated_schema'
require './spec/schema_classes/generated_a_record_schema'
require './spec/schema_classes/generated_an_enum_enum'

# For testing the generated class.
RSpec.describe Deimos::GeneratedSchema do

  describe 'class initialization' do

    it 'should initialize the class' do
      klass = described_class.new(
        a_string: 'some string',
        a_int: -1,
        a_long: 1000000000000,
        a_float: 1.2,
        a_double: 1.123456789123,
        an_enum: Deimos::GeneratedAnEnumEnum.new(an_enum: 'sym1'),
        an_array: [1,2],
        a_map: {'some key' => 'some string value', 'another_key' => 's'},
        timestamp: '2021-03-22 17:43:41 +0000',
        message_id: '73d9551b212128f0f2a9a5038239e646',
        a_record: Deimos::GeneratedARecordSchema.new(a_record_field: 'the actual field')
      )
      expect(klass).to be_instance_of(described_class)
    end

    it 'should initialize the class with a hash' do
      h = {
        :a_string => 'some string',
        :a_int => -1,
        :a_long => 1000000000000,
        :a_float => 1.2,
        :a_double => 1.123456789123,
        :an_enum => Deimos::GeneratedAnEnumEnum.new(an_enum: 'sym1'),
        :an_array => [1,2],
        :a_map => {'some key' => 'some string value', 'another_key' => 's'},
        :timestamp => '2021-03-22 17:43:41 +0000',
        :message_id => '73d9551b212128f0f2a9a5038239e646',
        :a_record => Deimos::GeneratedARecordSchema.new(a_record_field: 'the actual field')
      }
      klass = described_class.new(h)
      expect(klass).to be_instance_of(described_class)
      expect(klass.a_float).to eq(1.2)
      h_2 = {
        a_string: 'some string',
        a_int: -1,
        a_long: 1000000000000,
        a_float: 1.2,
        a_double: 1.123456789123,
        an_enum: Deimos::GeneratedAnEnumEnum.new(an_enum: 'sym1'),
        an_array: [1,2],
        a_map: {'some key' => 'some string value', 'another_key' => 's'},
        timestamp: '2021-03-22 17:43:41 +0000',
        message_id: '73d9551b212128f0f2a9a5038239e646',
        a_record: Deimos::GeneratedARecordSchema.new(a_record_field: 'the actual field')
      }
      klass_2 = described_class.new(h_2)
      expect(klass_2).to be_instance_of(described_class)
      expect(klass_2.timestamp).to eq('2021-03-22 17:43:41 +0000')
    end

  end

  describe 'base class methods' do
    let(:klass) { described_class.new(
      a_string: 'some string',
      a_int: -1,
      a_long: 1000000000000,
      a_float: 1.2,
      a_double: 1.123456789123,
      an_enum: Deimos::GeneratedAnEnumEnum.new(an_enum: 'sym1'),
      an_array: [1,2],
      a_map: {'some key' => 'some string value', 'another_key' => 's'},
      timestamp: '2021-03-22 17:43:41 +0000',
      message_id: '73d9551b212128f0f2a9a5038239e646',
      a_record: Deimos::GeneratedARecordSchema.new(a_record_field: 'the actual field')
    ) }

    it 'should return the name of the schema and namespace' do
      expect(klass.schema).to eq('Generated')
      expect(klass.namespace).to eq('com.my-namespace')
      expect(klass.full_schema).to eq('com.my-namespace.Generated')
    end

    it 'should return an array of all fields in the schema' do
      klass.schema_fields.should match_array(%w[a_string a_int a_long a_float a_double an_enum an_array a_map timestamp message_id a_record])
    end

    it 'should return a hash of the payload' do
      payload_h = {
        'a_string' => 'some string',
        'a_int' => -1,
        'a_long' => 1000000000000,
        'a_float' => 1.2,
        'a_double' => 1.123456789123,
        'an_enum' => 'sym1',
        'an_array' => [1,2],
        'a_map' => {'some key' => 'some string value', 'another_key' => 's'},
        'timestamp' => '2021-03-22 17:43:41 +0000',
        'message_id' => '73d9551b212128f0f2a9a5038239e646',
        'a_record' => {'a_record_field' => 'the actual field'}
      }
      expect(klass.as_hash).to eq(payload_h)
    end

    it 'should return a JSON string of the payload' do
      s = '{"a_string":"some string","a_int":-1,"a_long":1000000000000,"a_float":1.2,"a_double":1.123456789123,"an_enum":"sym1","an_array":[1,2],"a_map":{"some key":"some string value","another_key":"s"},"timestamp":"2021-03-22 17:43:41 +0000","message_id":"73d9551b212128f0f2a9a5038239e646","a_record":{"a_record_field":"the actual field"}}'
      expect(klass.to_json).to eq(s)
    end

  end

  describe 'getters and setters' do
    let(:klass) { described_class.new(
      a_string: 'some string',
      a_int: -1,
      a_long: 1000000000000,
      a_float: 1.2,
      a_double: 1.123456789123,
      an_enum: Deimos::GeneratedAnEnumEnum.new(an_enum: 'sym1'),
      an_array: [1,2],
      a_map: {'some key' => 'some string value', 'another_key' => 's'},
      timestamp: '2021-03-22 17:43:41 +0000',
      message_id: '73d9551b212128f0f2a9a5038239e646',
      a_record: Deimos::GeneratedARecordSchema.new(a_record_field: 'the actual field')
    ) }

    it 'should get each value' do
      expect(klass.a_string).to eq('some string')
      expect(klass.a_int).to eq(-1)
      expect(klass.a_long).to eq(1000000000000)
      expect(klass.a_float).to eq(1.2)
      expect(klass.a_double).to eq(1.123456789123)
      expect(klass.an_enum).to be_instance_of(Deimos::GeneratedAnEnumEnum)
      expect(klass.an_array).to eq([1,2])
      expect(klass.a_map).to eq({'some key' => 'some string value', 'another_key' => 's'})
      expect(klass.timestamp).to eq('2021-03-22 17:43:41 +0000')
      expect(klass.message_id).to eq('73d9551b212128f0f2a9a5038239e646')
      expect(klass.a_record).to be_instance_of(Deimos::GeneratedARecordSchema)
    end

    it 'should get the value of an_enum' do
      an_enum = klass.an_enum
      expect(an_enum).to be_instance_of(Deimos::GeneratedAnEnumEnum)
      expect(an_enum.an_enum).to eq('sym1')
    end

    it 'should get the value of a_record' do
      record = klass.a_record
      expect(record).to be_instance_of(Deimos::GeneratedARecordSchema)
      expect(record.a_record_field).to eq('the actual field')
      expect(record.as_hash).to eq({ "a_record_field" => 'the actual field' })
    end

    it 'should modify the value of a_string' do
      expect(klass.a_string).to eq('some string')
      klass.a_string = 'think different'
      expect(klass.a_string).to eq('think different')
    end

    it 'should modify the value of an_enum' do
      expect(klass.an_enum.an_enum).to eq('sym1')
      klass.an_enum.an_enum = 'sym2'
      expect(klass.an_enum.an_enum).to eq('sym2')
      klass.an_enum = Deimos::GeneratedAnEnumEnum.new(an_enum: 'sym1')
      expect(klass.an_enum.an_enum).to eq('sym1')
    end

    it 'should modify the value of a_record' do
      record = klass.a_record
      expect(record).to be_instance_of(Deimos::GeneratedARecordSchema)
      record = klass.a_record
      expect(record.a_record_field).to eq('the actual field')
      expect(record.as_hash).to eq({ "a_record_field" => 'the actual field' })
    end

  end

end
