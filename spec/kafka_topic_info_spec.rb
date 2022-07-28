# frozen_string_literal: true

each_db_config(Deimos::KafkaTopicInfo) do

  it 'should lock the topic' do
    expect(described_class.lock('my-topic', 'abc')).to be_truthy
    expect(described_class.lock('my-topic', 'def')).to be_falsey
    expect(described_class.lock('my-topic2', 'def')).to be_truthy
    expect(described_class.count).to eq(2)
    expect(described_class.first.locked_by).to eq('abc')
    expect(described_class.last.locked_by).to eq('def')
  end

  it "should lock the topic if it's old" do
    described_class.create!(topic: 'my-topic', locked_by: 'abc', error: true,
                            locked_at: 2.minutes.ago)
    expect(described_class.lock('my-topic', 'abc')).to be_truthy
    expect(described_class.count).to eq(1)
    expect(described_class.first.locked_by).to eq('abc')

  end

  it "should lock the topic if it's not currently locked" do
    described_class.create!(topic: 'my-topic', locked_by: nil,
                            locked_at: nil)
    expect(described_class.lock('my-topic', 'abc')).to be_truthy
    expect(described_class.count).to eq(1)
    expect(described_class.first.locked_by).to eq('abc')
  end

  it "should not lock the topic if it's errored" do
    described_class.create!(topic: 'my-topic', locked_by: nil,
                            locked_at: nil, error: true)
    expect(described_class.lock('my-topic', 'abc')).to be_falsey
    expect(described_class.count).to eq(1)
    expect(described_class.first.locked_by).to eq(nil)
  end

  specify '#clear_lock' do
    freeze_time do
      Deimos::KafkaTopicInfo.create!(topic: 'my-topic', locked_by: 'abc',
                                     locked_at: 10.seconds.ago, error: true, retries: 1,
                                     last_processed_at: 20.seconds.ago)
      Deimos::KafkaTopicInfo.create!(topic: 'my-topic2', locked_by: 'def',
                                     locked_at: 10.seconds.ago, error: true, retries: 1,
                                     last_processed_at: 20.seconds.ago)
      Deimos::KafkaTopicInfo.clear_lock('my-topic', 'abc')
      expect(Deimos::KafkaTopicInfo.count).to eq(2)
      record = Deimos::KafkaTopicInfo.first
      expect(record.locked_by).to eq(nil)
      expect(record.locked_at).to eq(nil)
      expect(record.error).to eq(false)
      expect(record.retries).to eq(0)
      expect(record.last_processed_at.in_time_zone.to_s).to eq(Time.zone.now.to_s)
      record = Deimos::KafkaTopicInfo.last
      expect(record.locked_by).not_to eq(nil)
      expect(record.locked_at).not_to eq(nil)
      expect(record.error).not_to eq(false)
      expect(record.retries).not_to eq(0)
      expect(record.last_processed_at.in_time_zone.to_s).to eq(20.seconds.ago.to_s)
    end
  end

  specify '#ping_empty_topics' do
    freeze_time do
      old_time = 1.hour.ago.to_s
      t1 = Deimos::KafkaTopicInfo.create!(topic: 'topic1', last_processed_at: old_time)
      t2 = Deimos::KafkaTopicInfo.create!(topic: 'topic2', last_processed_at: old_time)
      t3 = Deimos::KafkaTopicInfo.create!(topic: 'topic3', last_processed_at: old_time,
                                          locked_by: 'me', locked_at: 1.minute.ago)

      expect(Deimos::KafkaTopicInfo.count).to eq(3)
      Deimos::KafkaTopicInfo.all.each { |t| expect(t.last_processed_at.in_time_zone.to_s).to eq(old_time) }
      Deimos::KafkaTopicInfo.ping_empty_topics(%w(topic1))
      expect(t1.reload.last_processed_at.in_time_zone.to_s).to eq(old_time) # was passed as an exception
      expect(t2.reload.last_processed_at.in_time_zone.to_s).to eq(Time.zone.now.to_s)
      expect(t3.reload.last_processed_at.in_time_zone.to_s).to eq(old_time) # is locked
    end
  end

  specify '#register_error' do
    freeze_time do
      described_class.create!(topic: 'my-topic', locked_by: 'abc',
                              locked_at: 10.seconds.ago)
      described_class.create!(topic: 'my-topic2', locked_by: 'def',
                              locked_at: 10.seconds.ago, error: true, retries: 1)
      described_class.register_error('my-topic', 'abc')
      record = described_class.first
      expect(record.locked_by).to be_nil
      expect(record.locked_at).to eq(Time.zone.now)
      expect(record.error).to be_truthy
      expect(record.retries).to eq(1)

      described_class.register_error('my-topic2', 'def')
      record = described_class.last
      expect(record.error).to be_truthy
      expect(record.retries).to eq(2)
      expect(record.locked_at).to eq(Time.zone.now)
    end
  end

  specify '#heartbeat' do
    freeze_time do
      described_class.create!(topic: 'my-topic', locked_by: 'abc',
                              locked_at: 10.seconds.ago)
      described_class.heartbeat('my-topic', 'abc')
      expect(described_class.last.locked_at).to eq(Time.zone.now)
    end
  end

end
