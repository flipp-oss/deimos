# frozen_string_literal: true

require_relative 'avro_base_shared'
require 'deimos/schema_backends/avro_schema_registry'

RSpec.describe Deimos::SchemaBackends::AvroSchemaRegistry do
  let(:payload) do
    {
      'test_id' => 'some string',
      'some_int' => 3
    }
  end
  let(:backend) { described_class.new(schema: 'MySchema', namespace: 'com.my-namespace') }

  it_should_behave_like 'an Avro backend'

  it 'should encode and decode correctly' do
    schema_registry = instance_double(SchemaRegistry::Client)
    allow(schema_registry).to receive_messages(encode: 'encoded-payload', decode: payload)
    allow(backend).to receive(:schema_registry).and_return(schema_registry)
    results = backend.encode(payload, topic: 'topic')
    expect(results).to eq('encoded-payload')
    results = backend.decode(results)
    expect(results).to eq(payload)
    expect(schema_registry).to have_received(:encode).
      with(payload, schema_name: 'com.my-namespace.MySchema', subject: 'topic-value')
    expect(schema_registry).to have_received(:decode).
      with('encoded-payload')
  end

end
