# frozen_string_literal: true

RSpec.describe Deimos::Backends::KafkaAsync do
  include_context 'with publish_backend'
  it 'should publish to Kafka asynchronously' do
    producer = instance_double(Phobos::Producer::ClassMethods::PublicAPI)
    expect(producer).to receive(:async_publish_list).with(messages.map(&:encoded_hash))
    expect(described_class).to receive(:producer).and_return(producer)
    described_class.publish(producer_class: MyProducer, messages: messages)
  end
end
