# frozen_string_literal: true

RSpec.describe Deimos::Backends::KafkaAsync do
  include_context 'with publish_backend'
  it 'should publish to Kafka asynchronously' do
    expect(Karafka.producer).to receive(:produce_many_async).with(messages.map(&:encoded_hash))
    described_class.publish(producer_class: MyProducer, messages: messages)
  end
end
