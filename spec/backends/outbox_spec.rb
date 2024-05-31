# frozen_string_literal: true

each_db_config(Deimos::Backends::Outbox) do
  include_context 'with publish_backend'

  it 'should save to the database' do
    # expect(Deimos.config.metrics).to receive(:increment).with(
    #   'outbox.insert',
    #   tags: %w(topic:my-topic),
    #   by: 3
    # )
    described_class.publish(producer_class: MyProducer, messages: messages)
    records = Deimos::KafkaMessage.all
    expect(records.size).to eq(3)
    expect(records[0].attributes.to_h).to include(
      'message' => '{"test_id":"foo1","some_int":1}',
      'topic' => 'my-topic',
      'key' => '{"test_id":"foo1"}'
    )
    expect(records[1].attributes.to_h).to include(
      'message' => '{"test_id":"foo2","some_int":2}',
      'topic' => 'my-topic',
      'key' => '{"test_id":"foo2"}'
    )
    expect(records[2].attributes.to_h).to include(
      'message' => '{"test_id":"foo3","some_int":3}',
      'topic' => 'my-topic',
      'key' => '{"test_id":"foo3"}'
    )
  end

  it 'should add nil messages' do
    described_class.publish(producer_class: MyProducer,
                            messages: [build_message(nil, 'my-topic', 'foo1')])
    expect(Deimos::KafkaMessage.count).to eq(1)
    expect(Deimos::KafkaMessage.last.message).to eq(nil)
  end

  it 'should add to non-keyed messages' do
    orig_messages = messages.deep_dup
    described_class.publish(producer_class: MyNoKeyProducer,
                            messages: messages)
    expect(Deimos::KafkaMessage.count).to eq(3)
    described_class.publish(producer_class: MyNoKeyProducer,
                            messages: [orig_messages.first])
    expect(Deimos::KafkaMessage.count).to eq(4)
  end
end
