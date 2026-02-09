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

  describe 'with registry_info' do
    let(:registry_info) do
      Deimos::RegistryInfo.new('http://custom-registry:8081', 'custom-user', 'custom-password')
    end
    let(:backend_with_registry) do
      described_class.new(schema: 'MySchema', namespace: 'com.my-namespace', registry_info: registry_info)
    end

    it 'should store registry_info when provided' do
      expect(backend_with_registry.registry_info).to eq(registry_info)
      expect(backend_with_registry.registry_info.url).to eq('http://custom-registry:8081')
      expect(backend_with_registry.registry_info.user).to eq('custom-user')
      expect(backend_with_registry.registry_info.password).to eq('custom-password')
    end

    it 'should have nil registry_info when not provided' do
      backend_without_registry = described_class.new(schema: 'MySchema', namespace: 'com.my-namespace', registry_info: nil)
      expect(backend_without_registry.registry_info).to be_nil
    end
  end

end
