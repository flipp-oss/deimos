# frozen_string_literal: true

describe Deimos::SchemaBackends::Base do
  let(:backend) { described_class.new(schema: 'schema', namespace: 'namespace') }
  let(:payload) { { foo: 1 } }

  it 'should validate on encode' do
    expect(backend).to receive(:validate).with(payload, schema: 'schema')
    expect(backend).to receive(:encode_payload).with(payload, schema: 'schema', topic: 'topic')
    backend.encode(payload, topic: 'topic')
  end

  it 'should validate and encode a passed schema' do
    expect(backend).to receive(:validate).with(payload, schema: 'schema2')
    expect(backend).to receive(:encode_payload).with(payload, schema: 'schema2', topic: 'topic')
    backend.encode(payload, schema: 'schema2', topic: 'topic')
  end

  it 'should decode a schema' do
    expect(backend).to receive(:decode_payload).with(payload, schema: 'schema')
    backend.decode(payload)
  end

  it 'should decode a passed schema' do
    expect(backend).to receive(:decode_payload).with(payload, schema: 'schema2')
    backend.decode(payload, schema: 'schema2')
  end

end
