# frozen_string_literal: true

require 'deimos/schema_backends/proto_schema_registry'
require_relative "#{__dir__}/../gen/sample/v1/sample_pb"

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

  let(:backend) { described_class.new(schema: 'sample.v1.SampleMessage') }

  specify('#encode_key') do
    expect(backend.encode_key(nil, 789)).to eq('789')
    expect(backend.encode_key(nil, 'string')).to eq('string')
    expect(backend.encode_key(nil, { foo: 'bar' })).to eq('{"foo":"bar"}')
    expect(backend.encode_key(:foo, 'bar')).to eq('bar')
  end

  specify('#decode_key') do
    expect(backend.decode_key('789', nil)).to eq(789)
    expect(backend.decode_key('{"foo":"bar"}', :foo)).to eq('bar')
    expect(backend.decode_key('{"foo":"bar"}', nil)).to eq({ 'foo' => 'bar' })
  end

  it 'should encode and decode correctly' do
    proto_turf = instance_double(ProtoTurf)
    expect(proto_turf).to receive(:encode).
      with(payload, subject: 'topic').
      and_return('encoded-payload')
    expect(proto_turf).to receive(:decode).
      with('encoded-payload').
      and_return(payload)
    allow(described_class).to receive(:proto_turf).and_return(proto_turf)
    results = backend.encode(payload, topic: 'topic')
    expect(results).to eq('encoded-payload')
    results = backend.decode(results)
    expect(results).to eq(payload)
  end

end
