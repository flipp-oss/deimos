# frozen_string_literal: true

each_db_config(Deimos::Utils::DbProducer) do
  let(:producer) do
    producer = described_class.new
    allow(producer).to receive(:sleep)
    allow(producer).to receive(:producer).and_return(phobos_producer)
    producer
  end

  let(:phobos_producer) do
    pp = instance_double(Phobos::Producer::PublicAPI)
    allow(pp).to receive(:publish_list)
    pp
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

  describe '#produce_messages' do

    it 'should produce normally' do
      batch = ['A'] * 1000
      expect(phobos_producer).to receive(:publish_list).with(batch).once
      expect(Deimos.config.metrics).to receive(:increment).with('publish',
                                                                tags: %w(status:success topic:),
                                                                by: 1000).once
      producer.produce_messages(batch)
    end

    it 'should split the batch size on buffer overflow' do
      class_producer = double(Phobos::Producer::ClassMethods::PublicAPI, # rubocop:disable RSpec/VerifiedDoubles
                              sync_producer_shutdown: nil)
      allow(producer.class).to receive(:producer).and_return(class_producer)
      expect(class_producer).to receive(:sync_producer_shutdown).twice
      count = 0
      allow(phobos_producer).to receive(:publish_list) do
        count += 1
        raise Kafka::BufferOverflow if count < 3
      end
      allow(Deimos.config.metrics).to receive(:increment)
      batch = ['A'] * 1000
      producer.produce_messages(batch)
      expect(phobos_producer).to have_received(:publish_list).with(batch)
      expect(phobos_producer).to have_received(:publish_list).with(['A'] * 100)
      expect(phobos_producer).to have_received(:publish_list).with(['A'] * 10).exactly(100).times
      expect(Deimos.config.metrics).to have_received(:increment).with('publish',
                                                                      tags: %w(status:success topic:),
                                                                      by: 10).exactly(100).times
    end

    it "should raise an error if it can't split any more" do
      allow(phobos_producer).to receive(:publish_list) do
        raise Kafka::BufferOverflow
      end
      expect(Deimos.config.metrics).not_to receive(:increment)
      batch = ['A'] * 1000
      expect { producer.produce_messages(batch) }.to raise_error(Kafka::BufferOverflow)
      expect(phobos_producer).to have_received(:publish_list).with(batch)
      expect(phobos_producer).to have_received(:publish_list).with(['A'] * 100).once
      expect(phobos_producer).to have_received(:publish_list).with(['A'] * 10).once
      expect(phobos_producer).to have_received(:publish_list).with(['A']).once

    end

    describe '#compact_messages' do
      let(:batch) do
        [
          {
            key: 1,
            topic: 'my-topic',
            message: 'AAA'
          },
          {
            key: 2,
            topic: 'my-topic',
            message: 'BBB'
          },
          {
            key: 1,
            topic: 'my-topic',
            message: 'CCC'
          }
        ].map { |h| Deimos::KafkaMessage.create!(h) }
      end

      let(:deduped_batch) { batch[1..2] }

      it 'should dedupe messages when :all is set' do
        Deimos.configure { |c| c.db_producer.compact_topics = :all }
        expect(producer.compact_messages(batch)).to eq(deduped_batch)
      end

      it 'should dedupe messages when topic is included' do
        Deimos.configure { |c| c.db_producer.compact_topics = %w(my-topic my-topic2) }
        expect(producer.compact_messages(batch)).to eq(deduped_batch)
      end

      it 'should not dedupe messages when topic is not included' do
        Deimos.configure { |c| c.db_producer.compact_topics = %w(my-topic3 my-topic2) }
        expect(producer.compact_messages(batch)).to eq(batch)
      end

      it 'should not dedupe messages without keys' do
        unkeyed_batch = [
          {
            key: nil,
            topic: 'my-topic',
            message: 'AAA'
          },
          {
            key: nil,
            topic: 'my-topic',
            message: 'BBB'
          }
        ].map { |h| Deimos::KafkaMessage.create!(h) }
        Deimos.configure { |c| c.db_producer.compact_topics = :all }
        expect(producer.compact_messages(unkeyed_batch)).to eq(unkeyed_batch)
        Deimos.configure { |c| c.db_producer.compact_topics = [] }
      end

    end
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
      expect(producer).to receive(:send_pending_metrics).twice
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
      expect(Deimos.config.metrics).to receive(:increment).ordered.with(
        'db_producer.process',
        tags: %w(topic:my-topic),
        by: 2
      )
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
      expect(Deimos.config.metrics).to receive(:increment).ordered.with(
        'db_producer.process',
        tags: %w(topic:my-topic),
        by: 2
      )
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

    it 'should notify on error' do
      messages = (1..4).map do |i|
        Deimos::KafkaMessage.create!(
          id: i,
          topic: 'my-topic',
          message: "mess#{i}",
          partition_key: "key#{i}"
        )
      end

      expect(Deimos::KafkaTopicInfo).to receive(:lock).
        with('my-topic', 'abc').and_return(true)
      expect(producer).to receive(:produce_messages).and_raise('OH NOES')
      expect(producer).to receive(:retrieve_messages).and_return(messages)
      expect(Deimos::KafkaTopicInfo).to receive(:register_error)

      expect(Deimos::KafkaMessage.count).to eq(4)
      subscriber = Deimos.subscribe('db_producer.produce') do |event|
        expect(event.payload[:exception_object].message).to eq('OH NOES')
        expect(event.payload[:messages]).to eq(messages)
      end
      producer.process_topic('my-topic')
      # don't delete for regular errors
      expect(Deimos::KafkaMessage.count).to eq(4)
      Deimos.unsubscribe(subscriber)
    end

    it 'should delete messages on buffer overflow' do
      messages = (1..4).map do |i|
        Deimos::KafkaMessage.create!(
          id: i,
          topic: 'my-topic',
          message: "mess#{i}",
          partition_key: "key#{i}"
        )
      end

      expect(Deimos::KafkaTopicInfo).to receive(:lock).
        with('my-topic', 'abc').and_return(true)
      expect(producer).to receive(:produce_messages).and_raise(Kafka::BufferOverflow)
      expect(producer).to receive(:retrieve_messages).and_return(messages)
      expect(Deimos::KafkaTopicInfo).to receive(:register_error)

      expect(Deimos::KafkaMessage.count).to eq(4)
      producer.process_topic('my-topic')
      expect(Deimos::KafkaMessage.count).to eq(0)
    end

  end

  describe '#send_pending_metrics' do
    it 'should use the first created_at for each topic' do |example|
      # sqlite date-time strings don't work correctly
      next if example.metadata[:db_config][:adapter] == 'sqlite3'

      freeze_time do
        (1..2).each do |i|
          Deimos::KafkaMessage.create!(topic: "topic#{i}", message: nil,
                                       created_at: (3 + i).minutes.ago)
          Deimos::KafkaMessage.create!(topic: "topic#{i}", message: nil,
                                       created_at: (2 + i).minutes.ago)
          Deimos::KafkaMessage.create!(topic: "topic#{i}", message: nil,
                                       created_at: (1 + i).minute.ago)
        end
        allow(Deimos.config.metrics).to receive(:gauge)
        producer.send_pending_metrics
        expect(Deimos.config.metrics).to have_received(:gauge).twice
        expect(Deimos.config.metrics).to have_received(:gauge).
          with('pending_db_messages_max_wait', 4.minutes.to_i, tags: ['topic:topic1'])
        expect(Deimos.config.metrics).to have_received(:gauge).
          with('pending_db_messages_max_wait', 5.minutes.to_i, tags: ['topic:topic2'])
      end
    end

    it 'should send 0 if no messages' do
      expect(Deimos.config.metrics).to receive(:gauge).
        with('pending_db_messages_max_wait', 0)
      producer.send_pending_metrics
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
