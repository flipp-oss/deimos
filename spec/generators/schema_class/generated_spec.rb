# frozen_string_literal: true

# For testing the generated class.
RSpec.describe Deimos::Generated do
  let(:payload_hash) do
    {
      a_string: 'some string',
      a_int: -1,
      a_long: 1_000_000_000_000,
      a_float: 1.2,
      a_double: 1.123456789123,
      an_optional_int: nil,
      an_enum: Deimos::AnEnum.new('sym1'),
      an_array: [1, 2],
      a_map: { 'some key' => 'some string value', 'another_key' => 's' },
      timestamp: '2021-03-22 17:43:41 +0000',
      message_id: '73d9551b212128f0f2a9a5038239e646',
      a_record: Deimos::ARecord.new(a_record_field: 'the actual field')
    }
  end

  describe 'class initialization' do

    it 'should initialize the class from arguments' do
      klass = described_class.new(
        a_string: payload_hash[:a_string],
        a_int: payload_hash[:a_int],
        a_long: payload_hash[:a_long],
        a_float: payload_hash[:a_float],
        a_double: payload_hash[:a_double],
        an_optional_int: payload_hash[:an_optional_int],
        an_enum: payload_hash[:an_enum],
        an_array: payload_hash[:an_array],
        a_map: payload_hash[:a_map],
        timestamp: payload_hash[:timestamp],
        message_id: payload_hash[:message_id],
        a_record: payload_hash[:a_record]
      )
      expect(klass).to be_instance_of(described_class)
    end

    it 'should initialize the class from a hash with symbols as keys' do
      klass = described_class.new(payload_hash)
      expect(klass).to be_instance_of(described_class)
      expect(klass.a_float).to eq(1.2)
    end

    it 'should initialize the class from a hash with strings as keys' do
      string_payload = described_class.new(payload_hash).as_json
      klass = described_class.initialize_from_payload(string_payload)
      expect(klass).to be_instance_of(described_class)
      expect(klass.a_float).to eq(1.2)
      expect(klass.a_record).to be_instance_of(Deimos::ARecord)
      expect(klass.a_record.a_record_field).to eq("the actual field")
    end

  end

  describe 'base class methods' do
    let(:klass) do
      described_class.new(**payload_hash)
    end

    let(:schema_fields) do
      %w(a_string a_int a_long a_float a_double an_optional_int an_enum an_array a_map timestamp message_id a_record)
    end

    it 'should return the name of the schema and namespace' do
      expect(klass.schema).to eq('Generated')
      expect(klass.namespace).to eq('com.my-namespace')
      expect(klass.full_schema).to eq('com.my-namespace.Generated')
    end

    it 'should return an array of all fields in the schema' do
      expect(klass.schema_fields).to match_array(schema_fields)
    end

    it 'should return a hash of the payload' do
      described_class.new(**payload_hash)
      payload_h = {
        'a_string' => 'some string',
        'a_int' => -1,
        'a_long' => 1_000_000_000_000,
        'a_float' => 1.2,
        'a_double' => 1.123456789123,
        'an_optional_int' => nil,
        'an_enum' => 'sym1',
        'an_array' => [1, 2],
        'a_map' => { 'some key' => 'some string value', 'another_key' => 's' },
        'timestamp' => '2021-03-22 17:43:41 +0000',
        'message_id' => '73d9551b212128f0f2a9a5038239e646',
        'a_record' => { 'a_record_field' => 'the actual field' }
      }
      expect(klass.as_json).to eq(payload_h)
    end

    it 'should return a JSON string of the payload' do
      s = '{"a_string":"some string","a_int":-1,"a_long":1000000000000,"a_float":1.2,"a_double":1.123456789123,"an_optional_int":null,"an_enum":"sym1","an_array":[1,2],"a_map":{"some key":"some string value","another_key":"s"},"timestamp":"2021-03-22 17:43:41 +0000","message_id":"73d9551b212128f0f2a9a5038239e646","a_record":{"a_record_field":"the actual field"}}'
      expect(klass.to_json).to eq(s)
    end

  end

  describe 'getters and setters' do
    let(:klass) do
      described_class.new(payload_hash)
    end

    context 'getting' do
      it 'should get of values of primitive types' do
        expect(klass.a_string).to eq('some string')
        expect(klass.a_int).to eq(-1)
        expect(klass.a_long).to eq(1_000_000_000_000)
        expect(klass.a_float).to eq(1.2)
        expect(klass.a_double).to eq(1.123456789123)
        expect(klass.an_array).to eq([1, 2])
        expect(klass.timestamp).to eq('2021-03-22 17:43:41 +0000')
        expect(klass.message_id).to eq('73d9551b212128f0f2a9a5038239e646')
      end

      it 'should get the value of a_map' do
        expect(klass.a_map).to eq({ 'some key' => 'some string value', 'another_key' => 's' })
      end

      it 'should get the value of an optional field' do
        expect(klass.an_optional_int).to be_nil
      end

      it 'should get the value of an_enum' do
        an_enum = klass.an_enum
        expect(an_enum).to be_instance_of(Deimos::AnEnum)
        expect(an_enum.an_enum).to eq('sym1')
      end

      it 'should get the value of a_record' do
        record = klass.a_record
        expect(record).to be_instance_of(Deimos::ARecord)
        expect(record.a_record_field).to eq('the actual field')
        expect(record.as_json).to eq({ 'a_record_field' => 'the actual field' })
      end

      it 'should support Hash-style element access of values' do
        expect(klass['a_string']).to eq('some string')
        expect(klass['a_int']).to eq(-1)
        expect(klass['a_long']).to eq(1_000_000_000_000)
        expect(klass['a_float']).to eq(1.2)
        expect(klass['a_double']).to eq(1.123456789123)
        expect(klass['an_array']).to eq([1, 2])
      end
    end

    context 'setting' do
      it 'should modify the value of a_string' do
        expect(klass.a_string).to eq('some string')
        klass.a_string = 'think different'
        expect(klass.a_string).to eq('think different')
      end

      it 'should modify the value of an_optional_int' do
        expect(klass.an_optional_int).to be_nil
        klass.an_optional_int = 123_456
        expect(klass.an_optional_int).to eq(123_456)
      end

      it 'should modify the value of an_enum' do
        expect(klass.an_enum.an_enum).to eq('sym1')
        klass.an_enum.an_enum = 'sym2'
        expect(klass.an_enum.an_enum).to eq('sym2')
        klass.an_enum = Deimos::AnEnum.new('sym1')
        expect(klass.an_enum.an_enum).to eq('sym1')
      end

      it 'should modify the value of a_record' do
        record = klass.a_record
        expect(record).to be_instance_of(Deimos::ARecord)
        expect(record.a_record_field).to eq('the actual field')
        expect(record.as_json).to eq({ 'a_record_field' => 'the actual field' })
        klass.a_record = Deimos::ARecord.new(a_record_field: 'the new field')
        expect(klass.a_record.a_record_field).to eq('the new field')
        expect(klass.a_record.as_json).to eq({ 'a_record_field' => 'the new field' })
      end
    end
  end
end
