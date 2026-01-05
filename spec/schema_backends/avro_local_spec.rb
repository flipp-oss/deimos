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
    results = backend.encode(payload)
    expect(results).to start_with("Obj\u0001\u0004\u0014avro.codec\bnull\u0016avro.schema\x94")
    results = backend.decode(results)
    expect(results).to eq(payload)
  end

end
