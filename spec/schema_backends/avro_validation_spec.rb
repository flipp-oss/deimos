# frozen_string_literal: true

require_relative 'avro_base_shared'
require 'deimos/schema_backends/avro_validation'

RSpec.describe Deimos::SchemaBackends::AvroValidation do
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
    expect(results).to eq(payload.to_json)
    results = backend.decode(results)
    expect(results).to eq(payload)
  end

end
