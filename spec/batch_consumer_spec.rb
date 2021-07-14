# frozen_string_literal: true

# :nodoc:
module ConsumerTest
  describe Deimos::Consumer, 'Batch Consumer' do
    prepend_before(:each) do
      # :nodoc:
      consumer_class = Class.new(described_class) do
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

    describe 'consume_batch' do
      SCHEMA_CLASS_SETTINGS.each do |setting, use_schema_class|
        context "with Schema Class consumption #{setting}" do
          before(:each) do
            Deimos.configure { |config| config.consumers.use_schema_class = use_schema_class }
          end

          it 'should provide backwards compatibility for BatchConsumer class' do
            consumer_class = Class.new(Deimos::BatchConsumer) do
              schema 'MySchema'
              namespace 'com.my-namespace'
              key_config field: 'test_id'

              # :nodoc:
              def consume_batch(_payloads, _metadata)
                raise 'This should not be called unless call_original is set'
              end
            end
            stub_const('ConsumerTest::MyOldBatchConsumer', consumer_class)

            test_consume_batch(MyOldBatchConsumer, batch) do |received, _metadata|
              expect(received).to eq(batch)
            end
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
        end
      end
    end

    describe 'when reraising errors is disabled' do
      before(:each) do
        Deimos.configure { |config| config.consumers.reraise_errors = false }
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
      let(:keys) do
        batch.map { |v| v.slice('test_id') }
      end

      it 'should decode payloads for all messages in the batch' do
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
          expect(metadata[:first_offset]).to eq(1)
        end
      end

      it 'should decode plain keys for all messages in the batch' do
        consumer_class = Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config plain: true
        end
        stub_const('ConsumerTest::MyBatchConsumer', consumer_class)

        test_consume_batch('my_batch_consume_topic', batch, keys: [1, 2]) do |_received, metadata|
          expect(metadata[:keys]).to eq([1, 2])
        end
      end
    end

    describe 'timestamps' do
      before(:each) do
        # :nodoc:
        consumer_class = Class.new(described_class) do
          schema 'MySchemaWithDateTimes'
          namespace 'com.my-namespace'
          key_config plain: true

          # :nodoc:
          def consume_batch(_payloads, _metadata)
            raise 'This should not be called unless call_original is set'
          end
        end
        stub_const('ConsumerTest::MyBatchConsumer', consumer_class)
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

    describe 'logging' do
      before(:each) do
        # :nodoc:
        consumer_class = Class.new(described_class) do
          schema 'MySchemaWithUniqueId'
          namespace 'com.my-namespace'
          key_config plain: true

          # :nodoc:
          def consume_batch(_payloads, _metadata)
            raise 'This should not be called unless call_original is set'
          end
        end
        stub_const('ConsumerTest::MyBatchConsumer', consumer_class)
        allow(Deimos.config.metrics).to receive(:histogram)
      end

      it 'should log message identifiers' do
        batch_with_message_id = [
          { 'id' => 1, 'test_id' => 'foo', 'some_int' => 5,
            'timestamp' => 3.minutes.ago.to_s, 'message_id' => 'one' },
          { 'id' => 2, 'test_id' => 'bar', 'some_int' => 6,
            'timestamp' => 2.minutes.ago.to_s, 'message_id' => 'two' }
        ]

        allow(Deimos.config.logger).
          to receive(:info)

        expect(Deimos.config.logger).
          to receive(:info).
          with(hash_including(
                 message_ids: [
                   { key: 1, message_id: 'one' },
                   { key: 2, message_id: 'two' }
                 ]
               )).
          twice

        test_consume_batch('my_batch_consume_topic', batch_with_message_id, keys: [1, 2])
      end
    end
  end
end
