# frozen_string_literal: true

describe Deimos::Utils::LagReporter do

  let(:kafka_client) { instance_double(Kafka::Client) }
  let(:partition1_tags) { %w(consumer_group:group1 partition:1 topic:my-topic) }
  let(:partition2_tags) { %w(consumer_group:group1 partition:2 topic:my-topic) }

  before(:each) do
    allow(kafka_client).to receive(:last_offset_for).and_return(100)
    allow(Phobos).to receive(:create_kafka_client).and_return(kafka_client)
    Deimos.configure { |c| c.consumers.report_lag = true }
  end

  after(:each) do
    described_class.reset
    Deimos.configure { |c| c.consumers.report_lag = false }
  end

  it 'should not report lag before ready' do
    expect(Deimos.config.metrics).not_to receive(:gauge)
    ActiveSupport::Notifications.instrument(
      'heartbeat.consumer.kafka',
      group_id: 'group1', topic_partitions: { 'my-topic': [1] }
    )
  end

  it 'should report lag' do
    expect(Deimos.config.metrics).to receive(:gauge).ordered.twice.
      with('consumer_lag', 95, tags: partition1_tags)
    expect(Deimos.config.metrics).to receive(:gauge).ordered.once.
      with('consumer_lag', 80, tags: partition2_tags)
    expect(Deimos.config.metrics).to receive(:gauge).ordered.once.
      with('consumer_lag', 0, tags: partition2_tags)
    ActiveSupport::Notifications.instrument(
      'seek.consumer.kafka',
      offset: 5, topic: 'my-topic', group_id: 'group1', partition: 1
    )
    ActiveSupport::Notifications.instrument(
      'start_process_message.consumer.kafka',
      offset: 20, topic: 'my-topic', group_id: 'group1', partition: 2
    )
    ActiveSupport::Notifications.instrument(
      'heartbeat.consumer.kafka',
      group_id: 'group1', topic_partitions: { 'my-topic': [1, 2] }
    )
    ActiveSupport::Notifications.instrument(
      'start_process_batch.consumer.kafka',
      last_offset: 100, topic: 'my-topic', group_id: 'group1', partition: 2
    )
    ActiveSupport::Notifications.instrument(
      'heartbeat.consumer.kafka',
      group_id: 'group1', topic_partitions: { 'my-topic': [1, 2] }
    )
  end

  it 'should update lag after heartbeat' do
    expect(Deimos.config.metrics).to receive(:gauge).ordered.once.
      with('consumer_lag', 94, tags: partition2_tags)
    expect(Deimos.config.metrics).to receive(:gauge).ordered.once.
      with('consumer_lag', 95, tags: partition2_tags)
    ActiveSupport::Notifications.instrument(
      'seek.consumer.kafka',
      offset: 6, topic: 'my-topic', group_id: 'group1', partition: 2
    )
    ActiveSupport::Notifications.instrument(
      'heartbeat.consumer.kafka',
      group_id: 'group1', topic_partitions: { 'my-topic': [1, 2] }
    )
    allow(kafka_client).to receive(:last_offset_for).and_return(101)
    ActiveSupport::Notifications.instrument(
      'heartbeat.consumer.kafka',
      group_id: 'group1', topic_partitions: { 'my-topic': [1, 2] }
    )
  end
end
