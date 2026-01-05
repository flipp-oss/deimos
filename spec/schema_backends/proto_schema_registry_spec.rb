# frozen_string_literal: true

require 'deimos/schema_backends/proto_schema_registry'
require_relative "#{__dir__}/../gen/sample/v1/sample_pb"
require_relative "#{__dir__}/../gen/sample/v1/sample_key_pb"

RSpec.describe Deimos::SchemaBackends::ProtoSchemaRegistry do
  let(:payload) do
    Sample::V1::SampleMessage.new(
      str: 'string',
      num: 123,
      str_arr: %w(one two),
      flag: true,
      timestamp: Time.utc(2017, 1, 1),
      nested: Sample::V1::NestedMessage.new(nested_str: 'string'),
      non_union_nested: Sample::V1::NestedMessage.new(nested_num: 456),
      str_map: { 'foo' => 'bar' }
    )
  end
  let(:schema_registry) { instance_double(SchemaRegistry::Client) }
  let(:key_schema_registry) { instance_double(SchemaRegistry::Client) }

  let(:backend) { described_class.new(schema: 'sample.v1.SampleMessage') }

  before(:each) do
    allow(described_class).to receive_messages(schema_registry: schema_registry, key_schema_registry: key_schema_registry)
  end

  describe 'payload encoding and decoding' do
    it 'should encode and decode payloads correctly' do
      allow(schema_registry).to receive_messages(encode: 'encoded-payload', decode: payload)

      # Encode
      encoded = backend.encode(payload, topic: 'topic')
      expect(encoded).to eq('encoded-payload')
      expect(schema_registry).to have_received(:encode).with(payload, subject: 'topic-value')

      # Decode
      decoded = backend.decode(encoded)
      expect(decoded).to eq(payload)
      expect(schema_registry).to have_received(:decode).with('encoded-payload')
    end

    it 'should encode hash payloads by converting to protobuf message' do
      hash_payload = {
        str: 'string',
        num: 123,
        flag: true
      }
      allow(schema_registry).to receive(:encode).and_return('encoded-payload')

      backend.encode(hash_payload, topic: 'topic')

      # Should have converted hash to protobuf message before encoding
      expect(schema_registry).to have_received(:encode) do |arg, **kwargs|
        expect(arg).to be_a(Sample::V1::SampleMessage)
        expect(arg.str).to eq('string')
        expect(arg.num).to eq(123)
        expect(arg.flag).to be(true)
        expect(kwargs).to eq(subject: 'topic-value')
      end
    end
  end

  describe 'key encoding with key_config field (auto-generated JSON schema)' do
    it 'should encode a simple field key using JSON schema' do
      key_hash = { 'str' => 'test-key' }

      allow(key_schema_registry).to receive(:encode).and_return('encoded-key')

      # encode_key is called from encode_proto_key with the hash
      encoded = backend.encode_key('str', 'test-key', topic: 'my-topic')

      expect(key_schema_registry).to have_received(:encode).with(
        key_hash,
        subject: 'my-topic-key',
        schema_text: anything
      )
      expect(encoded).to eq('encoded-key')
    end

    it 'should encode a hash key with field extraction using JSON schema' do
      full_payload = { 'str' => 'test-key', 'num' => 123 }
      key_hash = { 'str' => 'test-key' }

      allow(key_schema_registry).to receive(:encode).and_return('encoded-key')

      encoded = backend.encode_key('str', full_payload, topic: 'my-topic')

      expect(key_schema_registry).to have_received(:encode).with(
        key_hash,
        subject: 'my-topic-key',
        schema_text: anything
      )
      expect(encoded).to eq('encoded-key')
    end

    it 'should decode a JSON schema key' do
      decoded_json = { 'str' => 'test-key' }
      allow(key_schema_registry).to receive(:decode).and_return(decoded_json)

      result = backend.decode_key('encoded-key', 'str')

      expect(key_schema_registry).to have_received(:decode).with('encoded-key')
      expect(result).to eq('test-key')
    end

    it 'should decode a JSON schema key without field extraction' do
      decoded_json = { 'str' => 'test-key', 'num' => 123 }
      allow(key_schema_registry).to receive(:decode).and_return(decoded_json)

      result = backend.decode_key('encoded-key', nil)

      expect(key_schema_registry).to have_received(:decode).with('encoded-key')
      expect(result).to eq(decoded_json)
    end
  end

  describe 'key encoding with key_config schema (separate Protobuf schema)' do
    let(:key_backend) { described_class.new(schema: 'sample.v1.SampleMessageKey') }
    let(:key_schema_registry_for_test) { instance_double(SchemaRegistry::Client) }
    let(:schema_registry_for_test) { instance_double(SchemaRegistry::Client) }

    before(:each) do
      # For key_backend tests, mock both schema_registry instances
      allow(described_class).to receive_messages(schema_registry: schema_registry_for_test,
                                                 key_schema_registry:  key_schema_registry_for_test)
    end

    it 'should encode a protobuf key message using the key schema' do
      key_msg = Sample::V1::SampleMessageKey.new(str: 'test-key')
      # Since subject ends with '-key', encode_payload uses key_schema_registry
      allow(key_schema_registry_for_test).to receive(:encode).and_return('encoded-key')

      encoded = key_backend.encode(key_msg, topic: 'my-topic', is_key: true)

      expect(key_schema_registry_for_test).to have_received(:encode).with(key_msg, subject: 'my-topic-key')
      expect(encoded).to eq('encoded-key')
    end

    it 'should encode a hash key using the key schema' do
      key_hash = { str: 'test-key' }
      allow(key_schema_registry_for_test).to receive(:encode).and_return('encoded-key')

      encoded = key_backend.encode(key_hash, topic: 'my-topic', is_key: true)

      expect(key_schema_registry_for_test).to have_received(:encode) do |arg, **kwargs|
        expect(arg).to be_a(Sample::V1::SampleMessageKey)
        expect(arg.str).to eq('test-key')
        expect(kwargs).to eq(subject: 'my-topic-key')
      end
      expect(encoded).to eq('encoded-key')
    end

    it 'should decode a protobuf key' do
      key_msg = Sample::V1::SampleMessageKey.new(str: 'test-key')
      allow(schema_registry_for_test).to receive(:decode).and_return(key_msg)

      decoded = key_backend.decode('encoded-key')

      expect(schema_registry_for_test).to have_received(:decode).with('encoded-key')
      expect(decoded).to eq(key_msg)
    end
  end

  describe 'backward compatibility with plain string/JSON keys' do
    it 'should encode plain string keys as strings' do
      expect(backend.encode_key(nil, 'simple-string', topic: 'my-topic')).to eq('simple-string')
    end

    it 'should encode integer keys as strings' do
      expect(backend.encode_key(nil, 789, topic: 'my-topic')).to eq('789')
    end

    it 'should encode hash keys using JSON schema when no field specified' do
      key_hash = { foo: 'bar', baz: 'qux' }
      allow(key_schema_registry).to receive(:encode).and_return('encoded-json')

      backend.encode_key(nil, key_hash, topic: 'my-topic')

      # Should use encode_proto_key which calls key_schema_registry.encode
      expect(key_schema_registry).to have_received(:encode)
    end

    it 'should decode JSON string keys to hashes' do
      decoded_hash = { 'foo' => 'bar' }
      allow(key_schema_registry).to receive(:decode).and_return(decoded_hash)

      result = backend.decode_key('{"foo":"bar"}', nil)
      expect(result).to eq(decoded_hash)
    end

    it 'should decode JSON keys with field extraction' do
      decoded_hash = { 'foo' => 'bar', 'baz' => 'qux' }
      allow(key_schema_registry).to receive(:decode).and_return(decoded_hash)

      result = backend.decode_key('encoded-key', :foo)
      expect(result).to eq('bar')
    end
  end

  describe 'edge cases' do
    it 'should handle nested field extraction for keys' do
      # Use nested field from the actual schema: non_union_nested.nested_str
      nested_payload = { 'non_union_nested' => { 'nested_str' => 'value', 'nested_num' => 123 }, 'str' => 'other' }
      allow(key_schema_registry).to receive(:encode).and_return('encoded-key')

      backend.encode_key('non_union_nested.nested_str', nested_payload, topic: 'my-topic')

      # Should encode with just the nested_str field extracted from the nested message
      expect(key_schema_registry).to have_received(:encode).with(
        { 'nested_str' => 'value' },
        subject: 'my-topic-key',
        schema_text: anything
      )
    end

    it 'should handle encoding payloads with subject suffix detection' do
      allow(schema_registry).to receive(:encode).and_return('encoded-payload')
      allow(key_schema_registry).to receive(:encode).and_return('encoded-payload')

      # When subject ends with '-key', should use key_schema_registry
      backend.encode_payload(payload, subject: 'my-topic-key')
      expect(key_schema_registry).to have_received(:encode).with(payload, subject: 'my-topic-key')

      # When subject doesn't end with '-key', should use schema_registry
      backend.encode_payload(payload, subject: 'my-topic-value')
      expect(schema_registry).to have_received(:encode).with(payload, subject: 'my-topic-value')
    end

    it 'should handle nil payloads gracefully' do
      # encode with nil payload - schema_registry will handle the nil
      allow(schema_registry).to receive(:encode).with(nil, subject: 'topic-value').and_return(nil)
      expect(backend.encode(nil, topic: 'topic')).to be_nil

      # decode returns nil for nil payload (base class checks this)
      expect(backend.decode(nil)).to be_nil
    end
  end

  describe 'schema field introspection' do
    it 'should return schema fields from protobuf descriptor' do
      fields = backend.schema_fields

      expect(fields).to be_an(Array)
      expect(fields.map(&:name)).to include('str', 'num', 'str_arr', 'flag', 'timestamp')
    end
  end
end
