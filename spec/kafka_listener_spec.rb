# frozen_string_literal: true

describe Deimos::KafkaListener do
  include_context 'with widgets'

  prepend_before(:each) do
    producer_class = Class.new(Deimos::Producer) do
      schema 'MySchema'
      namespace 'com.my-namespace'
      topic 'my-topic'
      key_config none: true
    end
    stub_const('MyProducer', producer_class)
  end

  before(:each) do
    Deimos.configure do |c|
      c.producers.backend = :kafka
      c.schema.backend = :avro_local
    end
    allow_any_instance_of(Kafka::Cluster).to receive(:add_target_topics)
    allow_any_instance_of(Kafka::Cluster).to receive(:partitions_for).
      and_raise(Kafka::Error)
  end

  describe '.send_produce_error' do
    let(:payloads) do
      [{ 'test_id' => 'foo', 'some_int' => 123 },
       { 'test_id' => 'bar', 'some_int' => 124 }]
    end

    it 'should listen to publishing errors and republish as Deimos events' do
      allow(Deimos::Producer).to receive(:descendants).and_return([MyProducer])
      Deimos.subscribe('produce_error') do |event|
        expect(event.payload).to include(
          producer: MyProducer,
          topic: 'my-topic',
          payloads: payloads
        )
      end
      expect(Deimos.config.metrics).to receive(:increment).
        with('publish_error', tags: %w(topic:my-topic), by: 2)
      expect { MyProducer.publish_list(payloads) }.to raise_error(Kafka::DeliveryFailed)
    end

    it 'should not send any notifications when producer is not found' do
      Deimos.subscribe('produce_error') do |_|
        raise 'OH NOES'
      end
      allow(Deimos::Producer).to receive(:descendants).and_return([])
      expect(Deimos.config.metrics).not_to receive(:increment).with('publish_error', anything)
      expect { MyProducer.publish_list(payloads) }.to raise_error(Kafka::DeliveryFailed)
    end
  end
end
