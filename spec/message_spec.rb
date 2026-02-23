# frozen_string_literal: true

require_relative 'gen/sample/v1/sample_pb'

RSpec.describe(Deimos::Message) do
  it 'should detect tombstones' do
    expect(described_class.new(nil, key: 'key1')).
      to be_tombstone
    expect(described_class.new({ v: 'val1' }, key: 'key1')).
      not_to be_tombstone
    expect(described_class.new({ v: '' }, key: 'key1')).
      not_to be_tombstone
    expect(described_class.new({ v: 'val1' }, key: nil)).
      not_to be_tombstone
  end

  it 'can support complex keys/values' do
    expect { described_class.new({ a: 1, b: 2 }, key: { c: 3, d: 4 }) }.
      not_to raise_exception
  end

  describe 'headers' do
    it 'returns nil when not set' do
      expect(described_class.new({ v: 'val1' }, key: 'key1')).
        to have_attributes(headers: nil)
    end

    it 'can set and get headers' do
      expect(described_class.new({ v: 'val1' }, key: 'key1', headers: { a: 1 })).
        to have_attributes(headers: { a: 1 })
    end

    it 'includes headers when converting to Hash' do
      expect(described_class.new({ v: 'val1' }, key: 'key1', headers: { a: 1 }).to_h).
        to include(headers: { a: 1 })

      expect(described_class.new({ v: 'val1' }, key: 'key1', headers: { a: 1 }).encoded_hash).
        to include(headers: { a: 1 })
    end
  end

  describe '#add_fields' do
    context 'with Hash payloads' do
      it 'should add message_id if not present' do
        message = described_class.new({ some_field: 'value' }, key: 'key1')
        message.add_fields(%w(message_id timestamp))
        expect(message.payload['message_id']).to be_present
        expect(message.payload['message_id']).to match(/\A[0-9a-f-]{36}\z/)
      end

      it 'should not overwrite existing message_id' do
        message = described_class.new({ some_field: 'value', message_id: 'existing-id' }, key: 'key1')
        message.add_fields(%w(message_id timestamp))
        expect(message.payload['message_id']).to eq('existing-id')
      end

      it 'should add timestamp if not present' do
        freeze_time = Time.zone.local(2025, 1, 1, 12, 0, 0)
        travel_to(freeze_time) do
          message = described_class.new({ some_field: 'value' }, key: 'key1')
          message.add_fields(%w(message_id timestamp))
          expect(message.payload['timestamp']).to be_present
          expect(message.payload['timestamp']).to include('2025')
        end
      end

      it 'should not overwrite existing timestamp' do
        message = described_class.new({ some_field: 'value', timestamp: '2020-01-01' }, key: 'key1')
        message.add_fields(%w(message_id timestamp))
        expect(message.payload['timestamp']).to eq('2020-01-01')
      end

      it 'should not add fields that are not in the list' do
        message = described_class.new({ some_field: 'value' }, key: 'key1')
        message.add_fields(%w(other_field))
        expect(message.payload['message_id']).to be_nil
        expect(message.payload['timestamp']).to be_nil
      end

      it 'should do nothing for empty payload' do
        message = described_class.new({}, key: 'key1')
        message.add_fields(%w(message_id timestamp))
        expect(message.payload['message_id']).to be_nil
        expect(message.payload['timestamp']).to be_nil
      end

      it 'should do nothing for nil payload' do
        message = described_class.new(nil, key: 'key1')
        message.add_fields(%w(message_id timestamp))
        expect(message.payload).to be_nil
      end
    end

    context 'with Protobuf payloads' do
      it 'should add message_id to protobuf objects if not present' do
        proto_payload = Sample::V1::SampleMessage.new(str: 'test', num: 123)
        expect(proto_payload.message_id).to eq('')

        message = described_class.new(proto_payload, key: 'key1')
        message.add_fields(%w(message_id))

        expect(proto_payload.message_id).to match(/\A[0-9a-f-]{36}\z/)
      end

      it 'should not overwrite existing message_id on protobuf objects' do
        proto_payload = Sample::V1::SampleMessage.new(str: 'test', num: 123, message_id: 'existing-id')

        message = described_class.new(proto_payload, key: 'key1')
        message.add_fields(%w(message_id))

        expect(proto_payload.message_id).to eq('existing-id')
      end

      it 'should add timestamp to protobuf objects if not present' do
        proto_payload = Sample::V1::SampleMessage.new(str: 'test', num: 123)
        expect(proto_payload.timestamp).to be_nil

        message = described_class.new(proto_payload, key: 'key1')
        message.add_fields(%w(timestamp))

        expect(proto_payload.timestamp).to be_a(Google::Protobuf::Timestamp)
        expect(proto_payload.timestamp.seconds).to be > 0
      end

      it 'should not overwrite existing timestamp on protobuf objects' do
        existing_time = Google::Protobuf::Timestamp.new(seconds: 1_577_836_800) # 2020-01-01
        proto_payload = Sample::V1::SampleMessage.new(str: 'test', num: 123, timestamp: existing_time)

        message = described_class.new(proto_payload, key: 'key1')
        message.add_fields(%w(timestamp))

        expect(proto_payload.timestamp.seconds).to eq(1_577_836_800)
      end

      it 'should add both message_id and timestamp to protobuf objects' do
        proto_payload = Sample::V1::SampleMessage.new(str: 'test', num: 123)

        message = described_class.new(proto_payload, key: 'key1')
        message.add_fields(%w(message_id timestamp))

        expect(proto_payload.message_id).to match(/\A[0-9a-f-]{36}\z/)
        expect(proto_payload.timestamp).to be_a(Google::Protobuf::Timestamp)
      end

      it 'should not modify protobuf when field not in list' do
        proto_payload = Sample::V1::SampleMessage.new(str: 'test', num: 123)

        message = described_class.new(proto_payload, key: 'key1')
        message.add_fields(%w(other_field))

        expect(proto_payload.message_id).to eq('')
        expect(proto_payload.timestamp).to be_nil
      end

      it 'should handle protobuf with nested messages' do
        nested = Sample::V1::NestedMessage.new(nested_str: 'nested', nested_num: 456)
        proto_payload = Sample::V1::SampleMessage.new(str: 'test', num: 123, non_union_nested: nested)

        message = described_class.new(proto_payload, key: 'key1')
        message.add_fields(%w(message_id timestamp))

        expect(proto_payload.message_id).to match(/\A[0-9a-f-]{36}\z/)
        expect(proto_payload.timestamp).to be_a(Google::Protobuf::Timestamp)
        expect(proto_payload.non_union_nested.nested_str).to eq('nested')
      end
    end
  end
end
