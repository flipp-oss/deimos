# frozen_string_literal: true

describe Deimos::Utils::SeekListener do

  describe '#start_listener' do
    let(:consumer) { instance_double(Kafka::Consumer) }
    let(:handler) { class_double(Deimos::Utils::MessageBankHandler) }

    before(:each) do
      allow(handler).to receive(:start)
      allow(consumer).to receive(:subscribe)
      allow_any_instance_of(Phobos::Listener).to receive(:create_kafka_consumer).and_return(consumer)
      allow_any_instance_of(Kafka::Client).to receive(:last_offset_for).and_return(100)
      stub_const('Deimos::Utils::SeekListener::MAX_SEEK_RETRIES', 2)
    end

    it 'should seek offset' do
      allow(consumer).to receive(:seek)
      expect(consumer).to receive(:seek).once
      seek_listener = described_class.new({ handler: handler, group_id: 999, topic: 'test_topic' })
      seek_listener.start_listener
    end

    it 'should retry on errors when seeking offset' do
      allow(consumer).to receive(:seek).and_raise(StandardError)
      expect(consumer).to receive(:seek).twice
      seek_listener = described_class.new({ handler: handler, group_id: 999, topic: 'test_topic' })
      seek_listener.start_listener
    end
  end
end
