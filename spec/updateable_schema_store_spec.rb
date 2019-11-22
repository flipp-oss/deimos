# frozen_string_literal: true

describe AvroTurf::SchemaStore do

  it 'should add an in-memory schema' do
    schema_store = described_class.new(path: Deimos.config.schema.path)
    schema_store.load_schemas!
    found_schema = schema_store.find('MySchema', 'com.my-namespace').as_json
    expect(found_schema['name']).to eq('MySchema')
    expect(found_schema['namespace']).to eq('com.my-namespace')
    expect(found_schema['fields'].size).to eq(2)
    expect(found_schema['fields'][0]['type']['type_sym']).to eq('string')
    expect(found_schema['fields'][0]['name']).to eq('test_id')
    new_schema = {
      'namespace' => 'com.my-namespace',
      'name' => 'MyNewSchema',
      'type' => 'record',
      'doc' => 'Test schema',
      'fields' => [
        {
          'name' => 'my_id',
          'type' => 'int',
          'doc' => 'test int'
        }
      ]
    }
    schema_store.add_schema(new_schema)
    found_schema = schema_store.find('MyNewSchema', 'com.my-namespace').
      as_json
    expect(found_schema['name']).to eq('MyNewSchema')
    expect(found_schema['namespace']).to eq('com.my-namespace')
    expect(found_schema['fields'].size).to eq(1)
    expect(found_schema['fields'][0]['type']['type_sym']).to eq('int')
    expect(found_schema['fields'][0]['name']).to eq('my_id')
  end
end
