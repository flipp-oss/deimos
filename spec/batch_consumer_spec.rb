# frozen_string_literal: true

require 'deimos/batch_consumer'

# :nodoc:
module ConsumerTest
  describe Deimos::BatchConsumer do

    prepend_before(:each) do
      # :nodoc:
      consumer_class = Class.new(Deimos::BatchConsumer) do
        schema 'MySchema'
        namespace 'com.my-namespace'
        key_config field: 'test_id'

        # :nodoc:
        def consume_batch(_payloads, _metadata)
          raise 'This should not be called unless call_original is set'
        end
      end
      stub_const('ConsumerTest::MyBatchConsumer', consumer_class)
    end

    let(:batch) do
      [
        { 'test_id' => 'foo', 'some_int' => 123 },
        { 'test_id' => 'bar', 'some_int' => 456 }
      ]
    end

    let(:invalid_payloads) do
      batch.concat([{ 'invalid' => 'key' }])
    end


    it 'should consume a batch of messages' do
      test_consume_batch(MyBatchConsumer, batch) do |received, _metadata|
        expect(received).to eq(batch)
      end
    end

    it 'should consume a message on a topic' do
      test_consume_batch('my_batch_consume_topic', batch) do |received, _metadata|
        expect(received).to eq(batch)
      end
    end

    it 'should fail on an invalid message in the batch' do
      test_consume_batch_invalid_message(MyBatchConsumer, batch.concat(invalid_payloads))
    end

    describe 'when reraising errors is disabled' do
      before(:each) do
        Deimos.configure { |config| config.reraise_consumer_errors = false }
      end

      it 'should not fail when before_consume_batch fails' do
        expect {
          test_consume_batch(
            MyBatchConsumer,
            batch,
            skip_expectation: true
          ) { raise 'OH NOES' }
        }.not_to raise_error
      end

      it 'should not fail when consume_batch fails' do
        expect {
          test_consume_batch(
            MyBatchConsumer,
            invalid_payloads,
            skip_expectation: true
          )
        }.not_to raise_error
      end
    end

    describe 'decoding' do
      let (:keys) do
        batch.map { |v| v.slice('test_id') }
      end

      it 'should decode payloads for all messages in the batch' do
        expect_any_instance_of(Deimos::AvroDataDecoder).
          to receive(:decode).with(batch[0])
        expect_any_instance_of(Deimos::AvroDataDecoder).
          to receive(:decode).with(batch[1])

        test_consume_batch('my_batch_consume_topic', batch) do |received, _metadata|
          # Mock decoder simply returns the payload
          expect(received).to eq(batch)
        end
      end

      it 'should decode keys for all messages in the batch' do
        expect_any_instance_of(ConsumerTest::MyBatchConsumer).
          to receive(:decode_key).with(keys[0]).and_call_original
        expect_any_instance_of(ConsumerTest::MyBatchConsumer).
          to receive(:decode_key).with(keys[1]).and_call_original

        test_consume_batch('my_batch_consume_topic', batch, keys: keys) do |_received, metadata|
          # Mock decode_key extracts the value of the first field as the key
          expect(metadata[:keys]).to eq(%w(foo bar))
        end
      end
    end

    describe 'timestamps' do
      before(:each) do
        # :nodoc:
        consumer_class = Class.new(Deimos::BatchConsumer) do
          schema 'MySchemaWithDateTimes'
          namespace 'com.my-namespace'
          key_config plain: true

          # :nodoc:
          def consume_batch(_payloads, _metadata)
            raise 'This should not be called unless call_original is set'
          end
        end
        stub_const('ConsumerTest::MyBatchConsumer', consumer_class)
        stub_batch_consumer(consumer_class)
        allow(Deimos.config.metrics).to receive(:histogram)
      end

      let(:batch_with_time) do
        [
          {
            'test_id' => 'foo',
            'some_int' => 123,
            'updated_at' => Time.now.to_i,
            'timestamp' => 2.minutes.ago.to_s
          },
          {
            'test_id' => 'bar',
            'some_int' => 456,
            'updated_at' => Time.now.to_i,
            'timestamp' => 3.minutes.ago.to_s
          }
        ]
      end

      let(:invalid_times) do
        [
          {
            'test_id' => 'baz',
            'some_int' => 123,
            'updated_at' => Time.now.to_i,
            'timestamp' => 'yesterday morning'
          },
          {
            'test_id' => 'ok',
            'some_int' => 456,
            'updated_at' => Time.now.to_i,
            'timestamp' => ''
          },
          {
            'test_id' => 'hello',
            'some_int' => 456,
            'updated_at' => Time.now.to_i,
            'timestamp' => '1234567890'
          }
        ]
      end

      it 'should consume a batch' do
        expect(Deimos.config.metrics).
          to receive(:histogram).with('handler',
                                      a_kind_of(Numeric),
                                      tags: %w(time:time_delayed topic:my-topic)).twice

        test_consume_batch('my_batch_consume_topic', batch_with_time) do |received, _metadata|
          expect(received).to eq(batch_with_time)
        end
      end

      it 'should fail nicely and ignore timestamps with the wrong format' do
        batch = invalid_times.concat(batch_with_time)

        expect(Deimos.config.metrics).
          to receive(:histogram).with('handler',
                                      a_kind_of(Numeric),
                                      tags: %w(time:time_delayed topic:my-topic)).twice

        test_consume_batch('my_batch_consume_topic', batch) do |received, _metadata|
          expect(received).to eq(batch)
        end
      end
    end
  end
end
