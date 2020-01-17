# frozen_string_literal: true

require_relative 'avro_base_shared'
require 'deimos/schema_backends/avro_local'

RSpec.describe Deimos::SchemaBackends::AvroLocal do
  let(:payload) do
    {
      'test_id' => 'some string',
      'some_int' => 3
    }
  end
  let(:backend) { described_class.new(schema: 'MySchema', namespace: 'com.my-namespace') }

  it_should_behave_like 'an Avro backend'

  it 'should encode and decode correctly' do
    avro_turf = instance_double(AvroTurf)
    expect(avro_turf).to receive(:encode).
      with(payload, schema_name: 'MySchema', namespace: 'com.my-namespace').
      and_return('encoded-payload')
    expect(avro_turf).to receive(:decode).
      with('encoded-payload', schema_name: 'MySchema', namespace: 'com.my-namespace').
      and_return(payload)
    allow(backend).to receive(:avro_turf).and_return(avro_turf)
    results = backend.encode(payload)
    expect(results).to eq('encoded-payload')
    results = backend.decode(results)
    expect(results).to eq(payload)
  end

end
