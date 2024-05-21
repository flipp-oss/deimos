# frozen_string_literal: true

RSpec.describe Deimos::Backends::Kafka do
  include_context 'with publish_backend'
  it 'should publish to Kafka synchronously' do
    expect(Karafka.producer).to receive(:produce_many_sync).with(messages)
    described_class.publish(producer_class: MyProducer, messages: messages)
  end
end
