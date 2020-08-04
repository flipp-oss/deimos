# frozen_string_literal: true

# :nodoc:
module ProducerTest
  describe Deimos::Producer do

    prepend_before(:each) do
      producer_class = Class.new(Deimos::Producer) do
        schema 'MySchema'
        namespace 'com.my-namespace'
        topic 'my-topic'
        key_config field: 'test_id'
      end
      stub_const('MyProducer', producer_class)

      producer_class = Class.new(Deimos::Producer) do
        schema 'MySchemaWithId'
        namespace 'com.my-namespace'
        topic 'my-topic'
        key_config plain: true
      end
      stub_const('MyProducerWithID', producer_class)

      producer_class = Class.new(Deimos::Producer) do
        schema 'MySchema'
        namespace 'com.my-namespace'
        topic 'my-topic'
        key_config plain: true
        # :nodoc:
        def self.partition_key(payload)
          payload[:payload_key] ? payload[:payload_key] + '1' : nil
        end
      end
      stub_const('MyNonEncodedProducer', producer_class)

      producer_class = Class.new(Deimos::Producer) do
        schema 'MySchema'
        namespace 'com.my-namespace'
        topic 'my-topic2'
        key_config none: true
      end
      stub_const('MyNoKeyProducer', producer_class)

      producer_class = Class.new(Deimos::Producer) do
        schema 'MyNestedSchema'
        namespace 'com.my-namespace'
        topic 'my-topic'
        key_config field: 'test_id'
      end
      stub_const('MyNestedSchemaProducer', producer_class)

      producer_class = Class.new(Deimos::Producer) do
        schema 'MySchema'
        namespace 'com.my-namespace'
        topic 'my-topic2'
        key_config schema: 'MySchema-key'
      end
      stub_const('MySchemaProducer', producer_class)

      producer_class = Class.new(Deimos::Producer) do
        schema 'MySchema'
        namespace 'com.my-namespace'
        topic 'my-topic'
      end
      stub_const('MyErrorProducer', producer_class)

    end

    it 'should fail on invalid message with error handler' do
      subscriber = Deimos.subscribe('produce') do |event|
        expect(event.payload[:payloads]).to eq([{ 'invalid' => 'key' }])
      end
      expect(MyProducer.encoder).to receive(:validate).and_raise('OH NOES')
      expect { MyProducer.publish('invalid' => 'key', :payload_key => 'key') }.
        to raise_error('OH NOES')
      Deimos.unsubscribe(subscriber)
    end

    it 'should produce a message' do
      expect(described_class).to receive(:produce_batch).once.with(
        Deimos::Backends::Test,
        [
          Deimos::Message.new({ 'test_id' => 'foo', 'some_int' => 123 },
                              MyProducer,
                              topic: 'my-topic',
                              partition_key: 'foo',
                              key: 'foo'),
          Deimos::Message.new({ 'test_id' => 'bar', 'some_int' => 124 },
                              MyProducer,
                              topic: 'my-topic',
                              partition_key: 'bar',
                              key: 'bar')
        ]
      ).and_call_original

      MyProducer.publish_list(
        [{ 'test_id' => 'foo', 'some_int' => 123 },
         { 'test_id' => 'bar', 'some_int' => 124 }]
      )
      expect('my-topic').to have_sent('test_id' => 'foo', 'some_int' => 123)
      expect('your-topic').not_to have_sent('test_id' => 'foo', 'some_int' => 123)
      expect('my-topic').not_to have_sent('test_id' => 'foo2', 'some_int' => 123)
    end

    it 'should add a message ID' do
      payload = { 'test_id' => 'foo',
                  'some_int' => 123,
                  'message_id' => a_kind_of(String),
                  'timestamp' => a_kind_of(String) }
      expect(described_class).to receive(:produce_batch).once do |_, messages|
        expect(messages.size).to eq(1)
        expect(messages[0].to_h).
          to match(
            payload: payload,
            topic: 'my-topic',
            partition_key: 'key',
            metadata: {
              producer_name: 'MyProducerWithID',
              decoded_payload: payload
            },
            key: 'key'
          )
      end
      MyProducerWithID.publish_list(
        [{ 'test_id' => 'foo', 'some_int' => 123, :payload_key => 'key' }]
      )
    end

    it 'should not publish if publish disabled' do
      expect(described_class).not_to receive(:produce_batch)
      Deimos.configure { |c| c.producers.disabled = true }
      MyProducer.publish_list(
        [{ 'test_id' => 'foo', 'some_int' => 123 },
         { 'test_id' => 'bar', 'some_int' => 124 }]
      )
      expect(MyProducer.topic).not_to have_sent(anything)
    end

    it 'should not send messages if inside a disable_producers block' do
      Deimos.disable_producers do
        MyProducer.publish_list(
          [{ 'test_id' => 'foo', 'some_int' => 123 },
           { 'test_id' => 'bar', 'some_int' => 124 }]
        )
      end
      expect(MyProducer.topic).not_to have_sent(anything)
      MyProducer.publish_list(
        [{ 'test_id' => 'foo', 'some_int' => 123 },
         { 'test_id' => 'bar', 'some_int' => 124 }]
      )
      expect(MyProducer.topic).to have_sent(anything)
    end

    it 'should send messages after a crash' do
      expect {
        Deimos.disable_producers do
          raise 'OH NOES'
        end
      }.to raise_error('OH NOES')
      expect(Deimos).not_to be_producers_disabled
    end

    it 'should produce to a prefixed topic' do
      Deimos.configure { |c| c.producers.topic_prefix = 'prefix.' }
      payload = { 'test_id' => 'foo', 'some_int' => 123 }
      expect(described_class).to receive(:produce_batch).once do |_, messages|
        expect(messages.size).to eq(1)
        expect(messages[0].to_h).
          to eq(
            payload: payload,
            topic: 'prefix.my-topic',
            partition_key: 'foo',
            metadata: {
              producer_name: 'MyProducer',
              decoded_payload: payload
            },
            key: 'foo'
          )
      end

      MyProducer.publish_list([payload])
      Deimos.configure { |c| c.producers.topic_prefix = nil }
      expect(described_class).to receive(:produce_batch).once do |_, messages|
        expect(messages.size).to eq(1)
        expect(messages[0].to_h).
          to eq(
            payload: payload,
            topic: 'my-topic',
            partition_key: 'foo',
            metadata: {
              producer_name: 'MyProducer',
              decoded_payload: payload
            },
            key: 'foo'
          )
      end

      MyProducer.publish_list(
        [{ 'test_id' => 'foo', 'some_int' => 123 }]
      )
    end

    it 'should encode the key' do
      expect(MyProducer.encoder).to receive(:encode_key).with('test_id', 'foo', topic: 'my-topic-key')
      expect(MyProducer.encoder).to receive(:encode_key).with('test_id', 'bar', topic: 'my-topic-key')
      expect(MyProducer.encoder).to receive(:encode).with({
                                                            'test_id' => 'foo',
                                                            'some_int' => 123
                                                          }, { topic: 'my-topic-value' })
      expect(MyProducer.encoder).to receive(:encode).with({
                                                            'test_id' => 'bar',
                                                            'some_int' => 124
                                                          }, { topic: 'my-topic-value' })

      MyProducer.publish_list(
        [{ 'test_id' => 'foo', 'some_int' => 123 },
         { 'test_id' => 'bar', 'some_int' => 124 }]
      )
    end

    it 'should not encode with plaintext key' do
      expect(MyNonEncodedProducer.key_encoder).not_to receive(:encode_key)

      MyNonEncodedProducer.publish_list(
        [{ 'test_id' => 'foo', 'some_int' => 123, :payload_key => 'foo_key' },
         { 'test_id' => 'bar', 'some_int' => 124, :payload_key => 'bar_key' }]
      )
    end

    it 'should encode with a schema' do
      expect(MySchemaProducer.key_encoder).to receive(:encode).with({ 'test_id' => 'foo_key' },
                                                                    { topic: 'my-topic2-key' })
      expect(MySchemaProducer.key_encoder).to receive(:encode).with({ 'test_id' => 'bar_key' },
                                                                    { topic: 'my-topic2-key' })

      MySchemaProducer.publish_list(
        [{ 'test_id' => 'foo', 'some_int' => 123,
           :payload_key => { 'test_id' => 'foo_key' } },
         { 'test_id' => 'bar', 'some_int' => 124,
           :payload_key => { 'test_id' => 'bar_key' } }]
      )
    end

    it 'should properly encode and coerce values with a nested record' do
      expect(MyNestedSchemaProducer.encoder).to receive(:encode_key).with('test_id', 'foo', topic: 'my-topic-key')
      MyNestedSchemaProducer.publish(
        'test_id' => 'foo',
        'test_float' => BigDecimal('123.456'),
        'some_nested_record' => {
          'some_int' => 123,
          'some_float' => BigDecimal('456.789'),
          'some_string' => '123',
          'some_optional_int' => nil
        },
        'some_optional_record' => nil
      )
      expect(MyNestedSchemaProducer.topic).to have_sent(
        'test_id' => 'foo',
        'test_float' => 123.456,
        'some_nested_record' => {
          'some_int' => 123,
          'some_float' => 456.789,
          'some_string' => '123',
          'some_optional_int' => nil
        },
        'some_optional_record' => nil
      )
    end

    it 'should error with nothing set' do
      expect {
        MyErrorProducer.publish_list(
          [{ 'test_id' => 'foo', 'some_int' => 123, :payload_key => '123' }]
        )
      }.to raise_error('No key config given - if you are not encoding keys, please use `key_config plain: true`')
    end

    it 'should error if no key given and none is not the config' do
      expect {
        MyNonEncodedProducer.publish_list(
          [{ 'test_id' => 'foo', 'some_int' => 123 }]
        )
      }.to raise_error('No key given but a key is required! Use `key_config none: true` to avoid using keys.')
    end

    it 'should allow nil keys if none: true is configured' do
      expect {
        MyNoKeyProducer.publish_list(
          [{ 'test_id' => 'foo', 'some_int' => 123 }]
        )
      }.not_to raise_error
    end

    it 'should use a partition key' do
      MyNonEncodedProducer.publish_list([{
                                          'test_id' => 'foo',
                                          'some_int' => 123,
                                          :payload_key => '123'
                                        },
                                         {
                                           'test_id' => 'bar',
                                           'some_int' => 456,
                                           :payload_key => '456'
                                         }])
      expect(MyNonEncodedProducer.topic).to have_sent({
                                                        'test_id' => 'foo',
                                                        'some_int' => 123
                                                      }, '123', '1231')
      expect(MyNonEncodedProducer.topic).to have_sent({
                                                        'test_id' => 'bar',
                                                        'some_int' => 456
                                                      }, '456', '4561')
    end

    describe 'disabling' do
      it 'should disable globally' do
        Deimos.disable_producers do
          Deimos.disable_producers do # test nested
            MyProducer.publish(
              'test_id' => 'foo',
              'some_int' => 123,
              :payload_key => '123'
            )
            MyProducerWithID.publish(
              'test_id' => 'foo', 'some_int' => 123
            )
            expect('my-topic').not_to have_sent(anything)
            expect(Deimos).to be_producers_disabled
            expect(Deimos).to be_producers_disabled([MyProducer])
          end
        end

        MyProducerWithID.publish(
          'test_id' => 'foo', 'some_int' => 123, :payload_key => 123
        )
        expect('my-topic').
          to have_sent('test_id' => 'foo', 'some_int' => 123,
                       'message_id' => anything, 'timestamp' => anything)
        expect(Deimos).not_to be_producers_disabled
        expect(Deimos).not_to be_producers_disabled([MyProducer])
      end

      it 'should disable a single producer' do
        Deimos.disable_producers(MyProducer) do # test nested
          Deimos.disable_producers(MyProducer) do
            MySchemaProducer.publish(
              'test_id' => 'foo', 'some_int' => 123,
              :payload_key => { 'test_id' => 'foo_key' }
            )
            MyProducer.publish(
              'test_id' => 'foo',
              'some_int' => 123,
              :payload_key => '123'
            )
            expect('my-topic').not_to have_sent(anything)
            expect('my-topic2').to have_sent('test_id' => 'foo', 'some_int' => 123)
            expect(Deimos).not_to be_producers_disabled
            expect(Deimos).to be_producers_disabled(MyProducer)
            expect(Deimos).not_to be_producers_disabled(MySchemaProducer)
          end
        end
        expect(Deimos).not_to be_producers_disabled
        expect(Deimos).not_to be_producers_disabled(MyProducer)
        expect(Deimos).not_to be_producers_disabled(MySchemaProducer)
        MyProducer.publish(
          'test_id' => 'foo',
          'some_int' => 123,
          :payload_key => '123'
        )
        expect('my-topic').
          to have_sent('test_id' => 'foo', 'some_int' => 123)
      end

    end

    describe '#determine_backend_class' do
      before(:each) do
        Deimos.configure { |c| c.producers.backend = :kafka_async }
      end

      it 'should return kafka_async if sync is false' do
        expect(described_class.determine_backend_class(false, false)).
          to eq(Deimos::Backends::KafkaAsync)
        expect(described_class.determine_backend_class(nil, false)).
          to eq(Deimos::Backends::KafkaAsync)
      end

      it 'should return kafka if sync is true' do
        expect(described_class.determine_backend_class(true, false)).
          to eq(Deimos::Backends::Kafka)
      end

      it 'should return db if db is set' do
        Deimos.configure { producers.backend = :db }
        expect(described_class.determine_backend_class(true, false)).
          to eq(Deimos::Backends::Db)
        expect(described_class.determine_backend_class(false, false)).
          to eq(Deimos::Backends::Db)
      end

      it 'should return kafka if force_send is true' do
        Deimos.configure { producers.backend = :db }
        expect(described_class.determine_backend_class(true, true)).
          to eq(Deimos::Backends::Kafka)
        expect(described_class.determine_backend_class(false, true)).
          to eq(Deimos::Backends::KafkaAsync)
      end

      it 'should use the default sync if set' do
        expect(described_class.determine_backend_class(true, true)).
          to eq(Deimos::Backends::Kafka)
        expect(described_class.determine_backend_class(false, true)).
          to eq(Deimos::Backends::KafkaAsync)
        expect(described_class.determine_backend_class(nil, true)).
          to eq(Deimos::Backends::Kafka)
      end
    end

  end
end
