# frozen_string_literal: true

describe Deimos::SchemaBackends::Base do
  let(:backend) { described_class.new(schema: 'schema', namespace: 'namespace') }
  let(:payload) { { foo: 1 } }

  it 'should validate on encode' do
    expect(backend).to receive(:validate).with(payload, schema: 'schema')
    expect(backend).to receive(:encode_payload).with(payload, schema: 'schema', subject: 'topic-value')
    backend.encode(payload, topic: 'topic')
  end

  it 'should validate and encode a passed schema' do
    expect(backend).to receive(:validate).with(payload, schema: 'schema2')
    expect(backend).to receive(:encode_payload).with(payload, schema: 'schema2', subject: 'topic-value')
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

  it 'should use explicit schema as subject when topic is nil' do
    expect(backend).to receive(:validate).with(payload, schema: 'schema2')
    expect(backend).to receive(:encode_payload).with(payload, schema: 'schema2', subject: 'schema2-value')
    backend.encode(payload, schema: 'schema2')
  end

  it 'should use explicit schema as subject for key when topic is nil' do
    expect(backend).to receive(:validate).with(payload, schema: 'schema2')
    expect(backend).to receive(:encode_payload).with(payload, schema: 'schema2', subject: 'schema2-key')
    backend.encode(payload, schema: 'schema2', is_key: true)
  end

  it 'should return nil if passed nil' do
    expect(backend.decode(nil, schema: 'schema2')).to be_nil
  end

end
