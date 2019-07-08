# frozen_string_literal: true

each_db_config(Deimos::Utils::DbProducer) do
  let(:producer) do
    producer = described_class.new
    allow(producer).to receive(:sleep)
    phobos_producer = instance_double(Phobos::Producer::PublicAPI)
    allow(phobos_producer).to receive(:publish_list)
    allow(producer).to receive(:producer).and_return(phobos_producer)
    producer
  end

  before(:each) do
    stub_const('Deimos::Utils::DbProducer::BATCH_SIZE', 2)
  end

  specify '#process_next_messages' do
    expect(producer).to receive(:retrieve_topics).and_return(%w(topic1 topic2))
    expect(producer).to receive(:process_topic).twice
    expect(producer).to receive(:sleep).with(0.5)
    producer.process_next_messages
  end

  specify '#retrieve_topics' do
    (1..3).each do |i|
      Deimos::KafkaMessage.create!(topic: "topic#{i}",
                                   key: 'blergkey',
                                   message: 'blerg')
    end
    expect(producer.retrieve_topics).
      to contain_exactly('topic1', 'topic2', 'topic3')
  end

  specify '#retrieve_messages' do
    (1..3).each do |i|
      Deimos::KafkaMessage.create!(topic: 'topic1',
                                   message: 'blah',
                                   key: "key#{i}")
    end
    stub_const('Deimos::Utils::DbProducer::BATCH_SIZE', 5)
    producer.current_topic = 'topic1'
    messages = producer.retrieve_messages
    expect(messages.size).to eq(3)
    expect(messages).to all(be_a_kind_of(Deimos::KafkaMessage))
  end

  describe '#process_topic' do
    before(:each) do
      producer.id = 'abc'
    end

    it 'should do nothing if lock fails' do
      expect(Deimos::KafkaTopicInfo).to receive(:lock).
        with('my-topic', 'abc').and_return(false)
      expect(producer).not_to receive(:retrieve_messages)
      producer.process_topic('my-topic')
    end

    it 'should complete successfully' do
      messages = (1..4).map do |i|
        Deimos::KafkaMessage.new(
          topic: 'my-topic',
          message: "mess#{i}",
          partition_key: "key#{i}"
        )
      end
      expect(Deimos::KafkaTopicInfo).to receive(:lock).
        with('my-topic', 'abc').and_return(true)
      expect(producer).to receive(:retrieve_messages).ordered.
        and_return(messages[0..1])
      expect(producer).to receive(:produce_messages).ordered.with([
                                                                    {
                                                                      payload: 'mess1',
                                                                      key: nil,
                                                                      partition_key: 'key1',
                                                                      topic: 'my-topic'
                                                                    },
                                                                    {
                                                                      payload: 'mess2',
                                                                      key: nil,
                                                                      partition_key: 'key2',
                                                                      topic: 'my-topic'
                                                                    }
                                                                  ])
      expect(producer).to receive(:retrieve_messages).ordered.
        and_return(messages[2..3])
      expect(producer).to receive(:produce_messages).ordered.with([
                                                                    {
                                                                      payload: 'mess3',
                                                                      partition_key: 'key3',
                                                                      key: nil,
                                                                      topic: 'my-topic'
                                                                    },
                                                                    {
                                                                      payload: 'mess4',
                                                                      partition_key: 'key4',
                                                                      key: nil,
                                                                      topic: 'my-topic'
                                                                    }
                                                                  ])
      expect(producer).to receive(:retrieve_messages).ordered.
        and_return([])
      expect(Deimos::KafkaTopicInfo).to receive(:heartbeat).
        with('my-topic', 'abc').twice
      expect(Deimos::KafkaTopicInfo).to receive(:clear_lock).
        with('my-topic', 'abc').once
      producer.process_topic('my-topic')
    end

    it 'should register an error if it gets an error' do
      expect(producer).to receive(:retrieve_messages).and_raise('OH NOES')
      expect(Deimos::KafkaTopicInfo).to receive(:register_error).
        with('my-topic', 'abc')
      expect(producer).not_to receive(:produce_messages)
      producer.process_topic('my-topic')
    end

    it 'should move on if it gets a partial batch' do
      expect(producer).to receive(:retrieve_messages).ordered.
        and_return([Deimos::KafkaMessage.new(
          topic: 'my-topic',
          message: 'mess1'
        )])
      expect(producer).to receive(:produce_messages).once
      producer.process_topic('my-topic')
    end

  end

  example 'Full integration test' do
    (1..4).each do |i|
      (1..2).each do |j|
        Deimos::KafkaMessage.create!(topic: "topic#{j}",
                                     message: "mess#{i}",
                                     partition_key: "key#{i}")
        Deimos::KafkaMessage.create!(topic: "topic#{j + 2}",
                                     key: "key#{i}",
                                     partition_key: "key#{i}",
                                     message: "mess#{i}")
      end
    end
    allow(producer).to receive(:produce_messages)

    producer.process_next_messages
    expect(Deimos::KafkaTopicInfo.count).to eq(4)
    topics = Deimos::KafkaTopicInfo.select('distinct topic').map(&:topic)
    expect(topics).to contain_exactly('topic1', 'topic2', 'topic3', 'topic4')
    expect(Deimos::KafkaMessage.count).to eq(0)

    expect(producer).to have_received(:produce_messages).with([
                                                                {
                                                                  payload: 'mess1',
                                                                  partition_key: 'key1',
                                                                  key: nil,
                                                                  topic: 'topic1'
                                                                },
                                                                {
                                                                  payload: 'mess2',
                                                                  key: nil,
                                                                  partition_key: 'key2',
                                                                  topic: 'topic1'
                                                                }
                                                              ])
    expect(producer).to have_received(:produce_messages).with([
                                                                {
                                                                  payload: 'mess3',
                                                                  key: nil,
                                                                  partition_key: 'key3',
                                                                  topic: 'topic1'
                                                                },
                                                                {
                                                                  payload: 'mess4',
                                                                  key: nil,
                                                                  partition_key: 'key4',
                                                                  topic: 'topic1'
                                                                }
                                                              ])
    expect(producer).to have_received(:produce_messages).with([
                                                                {
                                                                  payload: 'mess1',
                                                                  key: 'key1',
                                                                  partition_key: 'key1',
                                                                  topic: 'topic3'
                                                                },
                                                                {
                                                                  payload: 'mess2',
                                                                  partition_key: 'key2',
                                                                  key: 'key2',
                                                                  topic: 'topic3'
                                                                }
                                                              ])
    expect(producer).to have_received(:produce_messages).with([
                                                                {
                                                                  payload: 'mess3',
                                                                  key: 'key3',
                                                                  partition_key: 'key3',
                                                                  topic: 'topic3'
                                                                },
                                                                {
                                                                  payload: 'mess4',
                                                                  partition_key: 'key4',
                                                                  key: 'key4',
                                                                  topic: 'topic3'
                                                                }
                                                              ])
  end

end
