# frozen_string_literal: true

each_db_config(Deimos::Backends::Db) do
  include_context 'with publish_backend'

  it 'should save to the database' do
    described_class.publish(producer_class: MyProducer, messages: messages)
    records = Deimos::KafkaMessage.all
    expect(records.size).to eq(3)
    expect(records[0].attributes.to_h).to include(
      'message' => '{"foo"=>1}',
      'topic' => 'my-topic',
      'key' => 'foo1'
    )
    expect(records[1].attributes.to_h).to include(
      'message' => '{"foo"=>2}',
      'topic' => 'my-topic',
      'key' => 'foo2'
    )
    expect(records[2].attributes.to_h).to include(
      'message' => '{"foo"=>3}',
      'topic' => 'my-topic',
      'key' => 'foo3'
    )
  end

  it 'should add nil messages' do
    described_class.publish(producer_class: MyProducer,
                            messages: [build_message(nil, 'my-topic', "foo1")])
    expect(Deimos::KafkaMessage.count).to eq(1)
  end

  it 'should add to non-keyed messages' do
    described_class.publish(producer_class: MyNoKeyProducer,
                            messages: messages)
    expect(Deimos::KafkaMessage.count).to eq(3)
    described_class.publish(producer_class: MyNoKeyProducer,
                            messages: [messages.first])
    expect(Deimos::KafkaMessage.count).to eq(4)

  end
end
