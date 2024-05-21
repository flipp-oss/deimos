# frozen_string_literal: true

RSpec.describe Deimos::Backends::Base do
  include_context 'with publish_backend'
  it 'should call execute' do
    expect(described_class).to receive(:execute).
      with(messages: messages, producer_class: MyProducer)
    described_class.publish(producer_class: MyProducer, messages: messages)
  end

  describe 'payload_log method' do
    it 'should return whole payload (default behavior)' do
      log_message = described_class.send(:log_message, MyProducer, messages)
      expect(log_message[:payloads].count).to eq(3)
      expect(log_message[:payloads].first[:payload]).to eq({ foo: 1 })
      expect(log_message[:payloads].first[:key]).to eq('foo1')
    end

    it 'should return only keys of messages' do
      set_karafka_config(:payload_log, :keys)
      log_message = described_class.send(:log_message, MyProducer, messages)
      expect(log_message[:payload_keys].count).to eq(3)
      expect(log_message[:payload_keys]).to be_a(Array)
      expect(log_message[:payload_keys].first).to eq('foo1')
    end

    it 'should return only messages count' do
      set_karafka_config(:payload_log, :count)
      log_message = described_class.send(:log_message, MyProducer, messages)
      expect(log_message[:payloads_count]).to be_a(Integer)
      expect(log_message[:payloads_count]).to eq(3)
    end
  end
end
