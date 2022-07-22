# frozen_string_literal: true

# For testing the generated class.
RSpec.describe Schemas::MySchemaWithCircularReference do
  let(:payload_hash) do
    {
      properties: {
        a_boolean: {
          'property' => true
        },
        an_integer: {
          'property' => 1
        },
        a_float: {
          'property' => 4.5
        },
        a_string: {
          'property' => 'string'
        },
        an_array: {
          'property' => [1, 2, 3]
        },
        an_hash: {
          'property' => {
            'a_key' => 'a_value'
          }
        }
      }
    }
  end

  describe 'class initialization' do
    it 'should initialize the class from keyword arguments' do
      klass = described_class.new(properties: payload_hash[:properties])
      expect(klass).to be_instance_of(described_class)
    end

    it 'should initialize the class from a hash with symbols as keys' do
      klass = described_class.new(**payload_hash)
      expect(klass).to be_instance_of(described_class)
    end

    it 'should initialize the class when missing attributes' do
      payload_hash.delete(:properties)
      klass = described_class.new(**payload_hash)
      expect(klass).to be_instance_of(described_class)
    end

  end

  describe 'base class methods' do
    let(:klass) do
      described_class.new(**payload_hash)
    end

    it 'should return the name of the schema and namespace' do
      expect(klass.schema).to eq('MySchemaWithCircularReference')
      expect(klass.namespace).to eq('com.my-namespace')
      expect(klass.full_schema).to eq('com.my-namespace.MySchemaWithCircularReference')
    end

    it 'should return a json version of the payload' do
      described_class.new(**payload_hash)
      payload_h = {
        'properties' => {
          a_boolean: {
            'property' =>true
          },
          an_integer: {
            'property' =>1
          },
          a_float: {
            'property' =>4.5
          },
          a_string: {
            'property' =>'string'
          },
          an_array: {
            'property' =>[1, 2, 3]
          },
          an_hash: {
            'property' =>{
              'a_key' => 'a_value'
            }
          }
        }
      }

      expect(klass.as_json).to eq(payload_h)
    end

    it 'should return a JSON string of the payload' do
      s = '{"properties":{"a_boolean":{"property":true},"an_integer":{"property":1},"a_float":{"property":4.5},"a_string":{"property":"string"},"an_array":{"property":[1,2,3]},"an_hash":{"property":{"a_key":"a_value"}}}}'
      expect(klass.to_json).to eq(s)
    end
  end
end
