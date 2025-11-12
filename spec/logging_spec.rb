# frozen_string_literal: true

RSpec.describe Deimos::Logging do
  include_context 'with publish_backend'
  describe '#messages_log_text' do
    it 'should return whole payload (default behavior)' do
      log_message = described_class.messages_log_text(:payloads, messages)
      expect(log_message[:payloads].count).to eq(3)
      expect(log_message[:payloads].first[:payload]).to eq({ some_int: 1, test_id: 'foo1' })
      expect(log_message[:payloads].first[:key]).to eq('foo1')
    end

    it 'should return only keys of messages' do
      log_message = described_class.messages_log_text(:keys, messages)
      expect(log_message[:payload_keys].count).to eq(3)
      expect(log_message[:payload_keys]).to be_a(Array)
      expect(log_message[:payload_keys].first).to eq('foo1')
    end

    it 'should return only messages count' do
      log_message = described_class.messages_log_text(:count, messages)
      expect(log_message[:payloads_count]).to be_a(Integer)
      expect(log_message[:payloads_count]).to eq(3)
    end
  end

end
