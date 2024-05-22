# frozen_string_literal: true

# :nodoc:
module ConsumerTest
  describe Deimos::Consumer, 'Batch Consumer' do
    let(:schema) { 'MySchema' }
    let(:use_schema_classes) { false }
    let(:reraise_errors) { false }
    let(:key_config) { { field: 'test_id' } }
    let(:consumer_class) do
      Class.new(described_class) do
        # :nodoc:
        def consume_batch
        end
      end
    end
    before(:each) do
      # :nodoc:
      stub_const('MyBatchConsumer', consumer_class)
      stub_const('ConsumerTest::MyBatchConsumer', consumer_class)
      klass = consumer_class
      route_schema = schema
      route_key = key_config
      route_use_classes = use_schema_classes
      Karafka::App.routes.redraw do
        topic 'my-topic' do
          consumer klass
          schema route_schema
          namespace 'com.my-namespace'
          key_config route_key
          use_schema_classes route_use_classes
        end
      end
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
      SCHEMA_CLASS_SETTINGS.each do |setting, use_schema_classes|
        context "with Schema Class consumption #{setting}" do

          let(:schema_class_batch) do
            batch.map do |p|
              Deimos::Utils::SchemaClass.instance(p, 'MySchema', 'com.my-namespace')
            end
          end
          let(:use_schema_classes) { true }

          before(:each) do
            Deimos.configure do |config|
              config.schema.use_full_namespace = true
            end
          end

          it 'should consume a batch of messages' do
            test_consume_batch(MyBatchConsumer, schema_class_batch) do |received|
              expect(received.payloads).to eq(schema_class_batch)
            end
          end

          it 'should consume a message on a topic' do
            test_consume_batch('my-topic', schema_class_batch) do |received|
              expect(received.payloads).to eq(schema_class_batch)
            end
          end
        end
      end
    end

    describe 'when reraising errors is disabled' do
      let(:reraise_errors) { false }

      it 'should not fail when before_consume_batch fails' do
        expect {
          test_consume_batch(
            MyBatchConsumer,
            batch
          ) do
            raise 'OH NOES'
          end
        }.not_to raise_error
      end

    end

    describe 'decoding' do
      let(:keys) do
        batch.map { |v| v.slice('test_id') }
      end

      it 'should decode payloads for all messages in the batch' do
        test_consume_batch('my-topic', batch) do
          # Mock decoder simply returns the payload
          expect(messages.payloads).to eq(batch)
        end
      end

      it 'should decode keys for all messages in the batch' do
        test_consume_batch('my-topic', batch, keys: keys) do
          expect(messages.map(&:key)).to eq([{'test_id' => 'foo'}, {'test_id' => 'bar'}])
        end
      end

      context 'with plain keys' do
        let(:key_config) { { plain: true } }
        it 'should decode plain keys for all messages in the batch' do
          test_consume_batch('my-topic', batch, keys: [1, 2]) do |_received, metadata|
            expect(metadata[:keys]).to eq([1, 2])
          end
        end
      end
    end

    describe 'timestamps' do
      let(:schema) { 'MySchemaWithDateTimes' }
      let(:key_config) { { none: true } }
      before(:each) do
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
        # expect(Deimos.config.metrics).
        #   to receive(:histogram).with('handler',
        #                               a_kind_of(Numeric),
        #                               tags: %w(time:time_delayed topic:my-topic)).twice

        test_consume_batch('my-topic', batch_with_time) do
          expect(messages.payloads).to eq(batch_with_time)
        end
      end

      it 'should fail nicely and ignore timestamps with the wrong format' do
        batch = invalid_times.concat(batch_with_time)

        # expect(Deimos.config.metrics).
        #   to receive(:histogram).with('handler',
        #                               a_kind_of(Numeric),
        #                               tags: %w(time:time_delayed topic:my-topic)).twice

        test_consume_batch('my-topic', batch) do
          expect(messages.payloads).to eq(batch)
        end
      end
    end

    describe 'logging' do
      let(:schema) { 'MySchemaWithUniqueId' }
      let(:key_config) { { plain: true } }
      before(:each) do
        allow(Deimos.config.metrics).to receive(:histogram)
      end

      it 'should log message identifiers' do
        batch_with_message_id = [
          { 'id' => 1, 'test_id' => 'foo', 'some_int' => 5,
            'timestamp' => 3.minutes.ago.to_s, 'message_id' => 'one' },
          { 'id' => 2, 'test_id' => 'bar', 'some_int' => 6,
            'timestamp' => 2.minutes.ago.to_s, 'message_id' => 'two' }
        ]

        allow(Deimos.config.logger).to receive(:info)

        expect(Deimos.config.logger).
          to receive(:info).
          with(hash_including(
                 message_ids: [
                   { key: "1", message_id: 'one' },
                   { key: "2", message_id: 'two' }
                 ]
               ))

        test_consume_batch('my-topic', batch_with_message_id, keys: [1, 2])
      end
    end
  end
end
