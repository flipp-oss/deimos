# frozen_string_literal: true

# For testing the generated class.
RSpec.describe Deimos::MySchemaWithComplexTypes do
  let(:payload_hash) do
    {
      test_id: 'test id',
      test_float: 1.2,
      test_array: %w(abc def),
      some_record: Deimos::ARecord.new(a_record_field: 'field 1'),
      some_optional_record: Deimos::ARecord.new(a_record_field: 'field 2'),
      some_record_array: [Deimos::ARecord.new(a_record_field: 'field 3'),
                          Deimos::ARecord.new(a_record_field: 'field 4')],
      some_record_map: {
        'record_1' => Deimos::ARecord.new(a_record_field: 'field 5'),
        'record_2' => Deimos::ARecord.new(a_record_field: 'field 6')
      },
      some_enum_array: [Deimos::AnEnum.new('sym1'),
                        Deimos::AnEnum.new('sym2')]
    }
  end

  describe 'class initialization' do

    it 'should initialize the class from keyword arguments' do
      klass = described_class.new(
        test_id: payload_hash[:test_id],
        test_float: payload_hash[:test_float],
        test_array: payload_hash[:test_array],
        some_record: payload_hash[:some_record],
        some_optional_record: payload_hash[:some_optional_record],
        some_record_array: payload_hash[:some_record_array],
        some_record_map: payload_hash[:some_record_map],
        some_enum_array: payload_hash[:some_enum_array]
      )
      expect(klass).to be_instance_of(described_class)
    end

    it 'should initialize the class from a hash with symbols as keys' do
      klass = described_class.new(**payload_hash)
      expect(klass).to be_instance_of(described_class)
    end

    it 'should initialize the class from a hash with strings as keys' do
      string_payload = described_class.new(**payload_hash).as_json
      klass = described_class.initialize_from_payload(string_payload)
      expect(klass).to be_instance_of(described_class)
    end

  end

  describe 'base class methods' do
    let(:klass) do
      described_class.new(**payload_hash)
    end

    let(:schema_fields) do
      %w(test_id test_float test_array some_record some_optional_record some_record_array some_record_map some_enum_array)
    end

    it 'should return the name of the schema and namespace' do
      expect(klass.schema).to eq('MySchemaWithComplexTypes')
      expect(klass.namespace).to eq('com.my-namespace')
      expect(klass.full_schema).to eq('com.my-namespace.MySchemaWithComplexTypes')
    end

    it 'should return an array of all fields in the schema' do
      expect(klass.schema_fields).to match_array(schema_fields)
    end

    it 'should return a json version of the payload' do
      described_class.new(**payload_hash)
      payload_h = {
        'test_id' => 'test id',
        'test_float' => 1.2,
        'test_array' => %w(abc def),
        'some_record' => { 'a_record_field' => 'field 1' },
        'some_optional_record' => { 'a_record_field' => 'field 2' },
        'some_record_array' => [
          { 'a_record_field' => 'field 3' },
          { 'a_record_field' => 'field 4' }
        ],
        'some_record_map' => {
          'record_1' => { 'a_record_field' => 'field 5' },
          'record_2' => { 'a_record_field' => 'field 6' }
        },
        'some_enum_array' => %w(sym1 sym2)
      }

      expect(klass.as_json).to eq(payload_h)
    end

    it 'should return a JSON string of the payload' do
      s = '{"test_id":"test id","test_float":1.2,"test_array":["abc","def"],"some_record":{"a_record_field":"field 1"},"some_optional_record":{"a_record_field":"field 2"},"some_record_array":[{"a_record_field":"field 3"},{"a_record_field":"field 4"}],"some_record_map":{"record_1":{"a_record_field":"field 5"},"record_2":{"a_record_field":"field 6"}},"some_enum_array":["sym1","sym2"]}'
      expect(klass.to_json).to eq(s)
    end
  end

  describe 'getters and setters' do
    let(:klass) do
      described_class.new(payload_hash)
    end

    context 'when getting attributes' do
      it 'should get of values of primitive types' do
        expect(klass.test_id).to eq('test id')
        expect(klass.test_float).to eq(1.2)
        expect(klass.test_array).to eq(%w(abc def))
      end

      it 'should get the value of some_record_array' do
        some_record_array = klass.some_record_array
        expect(some_record_array.first).to be_instance_of(Deimos::ARecord)
        expect(some_record_array.first.a_record_field).to eq('field 3')
      end

      it 'should get the value of some_record_map' do
        some_record_map = klass.some_record_map
        expect(some_record_map['record_1']).to be_instance_of(Deimos::ARecord)
        expect(some_record_map['record_1'].a_record_field).to eq('field 5')
      end

      it 'should get the value of some_enum_array' do
        some_enum_array = klass.some_enum_array
        expect(some_enum_array.first).to be_instance_of(Deimos::AnEnum)
        expect(some_enum_array.first.an_enum).to eq('sym1')
      end

      it 'should get the value of some_record' do
        record = klass.some_record
        expect(record).to be_instance_of(Deimos::ARecord)
        expect(record.a_record_field).to eq('field 1')
        expect(record.to_h).to eq({ 'a_record_field' => 'field 1' })
      end

      it 'should support Hash-style element access of values' do
        expect(klass['test_id']).to eq('test id')
        expect(klass['test_float']).to eq(1.2)
        expect(klass['test_array']).to eq(%w(abc def))
      end
    end

    context 'when setting attributes' do
      it 'should modify the value of test_id' do
        expect(klass.test_id).to eq('test id')
        klass.test_id = 'something different'
        expect(klass.test_id).to eq('something different')
      end

      it 'should modify the value of some_optional_record' do
        expect(klass.some_optional_record).to eq(Deimos::ARecord.new(a_record_field: 'field 2'))
        klass.some_optional_record = Deimos::ARecord.new(a_record_field: 'new field')
        expect(klass.some_optional_record).to eq(Deimos::ARecord.new(a_record_field: 'new field'))
        expect(klass.some_optional_record.as_json).to eq({ 'a_record_field' => 'new field' })
      end

      it 'should modify the value of some_enum_array' do
        klass.some_enum_array.first.an_enum = 'new_sym'
        expect(klass.some_enum_array.first).to eq(Deimos::AnEnum.new('new_sym'))
        klass.some_enum_array.second.an_enum = Deimos::AnEnum.new('other_sym')
        expect(klass.some_enum_array.second.an_enum).to eq('other_sym')
      end

      it 'should modify the value of some_record_map' do
        klass.some_record_map['record_1'].a_record_field = 'new field'
        expect(klass.some_record_map['record_1']).to eq(Deimos::ARecord.new(a_record_field: 'new field'))
        klass.some_record_map['record_2'] = Deimos::ARecord.new(a_record_field: 'other field')
        expect(klass.some_record_map['record_2']).to eq(Deimos::ARecord.new(a_record_field: 'other field'))
      end
    end
  end
end