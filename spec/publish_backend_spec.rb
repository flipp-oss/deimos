# frozen_string_literal: true

RSpec.describe Deimos::Backends::Base do
  include_context 'with publish_backend'
  it 'should call execute' do
    expect(described_class).to receive(:execute).
      with(messages: messages, producer_class: MyProducer)
    described_class.publish(producer_class: MyProducer, messages: messages)
  end
end
