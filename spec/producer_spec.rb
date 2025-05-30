# frozen_string_literal: true

# :nodoc:
module ProducerTest
  describe Deimos::Producer do

    prepend_before(:each) do
      producer_class = Class.new(Deimos::Producer)
      stub_const('MyProducer', producer_class)

      producer_class = Class.new(Deimos::Producer)
      stub_const('MyProducerWithID', producer_class)

      producer_class = Class.new(Deimos::Producer) do
        # :nodoc:
        def self.partition_key(payload)
          payload[:payload_key] ? payload[:payload_key] + '1' : nil
        end
      end
      stub_const('MyNonEncodedProducer', producer_class)

      producer_class = Class.new(Deimos::Producer)
      stub_const('MyNoKeyProducer', producer_class)

      producer_class = Class.new(Deimos::Producer)
      stub_const('MyNestedSchemaProducer', producer_class)

      producer_class = Class.new(Deimos::Producer)
      stub_const('MySchemaProducer', producer_class)

      producer_class = Class.new(Deimos::Producer)
      stub_const('MyErrorProducer', producer_class)

      Karafka::App.routes.redraw do
        topic 'my-topic' do
          producer_class MyProducer
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config field: 'test_id'
        end
        topic 'a-new-topic' do
          producer_class MyProducer
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config field: 'test_id'
        end
        topic 'my-topic-with-id' do
          producer_class MyProducerWithID
          schema 'MySchemaWithId'
          namespace 'com.my-namespace'
          key_config plain: true
        end
        topic 'my-topic-non-encoded' do
          producer_class MyNonEncodedProducer
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config plain: true
        end
        topic 'my-topic-no-key' do
          producer_class MyNoKeyProducer
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config none: true
        end
        topic 'my-topic-nested-schema' do
          producer_class MyNestedSchemaProducer
          schema 'MyNestedSchema'
          namespace 'com.my-namespace'
          key_config field: 'test_id'
        end
        topic 'my-topic-schema' do
          producer_class MySchemaProducer
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config schema: 'MySchema_key'
        end
        topic 'my-topic-error' do
          schema 'MySchema'
          namespace 'com.my-namespace'
          producer_class MyErrorProducer
        end
      end

    end

    it 'should fail on invalid message' do
      expect(Deimos::ProducerMiddleware).to receive(:call).and_raise('OH NOES')
      expect { MyProducer.publish({ 'invalid' => 'key', :payload_key => 'key' }) }.
        to raise_error('OH NOES')
    end

    it 'should produce a message' do
      expect(MyProducer).to receive(:produce_batch).once.with(
        Deimos::Backends::Kafka,
        [
          hash_including({
            payload: { 'test_id' => 'foo', 'some_int' => 123 },
            topic: 'my-topic',
            partition_key: nil
          }),
          hash_including({
            payload: { 'test_id' => 'bar', 'some_int' => 124 },
            topic: 'my-topic',
            partition_key: nil
          })
        ]
      ).and_call_original

      MyProducer.publish_list(
        [{ 'test_id' => 'foo', 'some_int' => 123 },
         { 'test_id' => 'bar', 'some_int' => 124 }]
      )
      expect('my-topic').to have_sent({'test_id' => 'foo', 'some_int' => 123}, 'foo', 'foo')
      expect('your-topic').not_to have_sent('test_id' => 'foo', 'some_int' => 123)
      expect('my-topic').not_to have_sent('test_id' => 'foo2', 'some_int' => 123)
    end

    it 'should allow setting the topic and headers from publish_list' do
      expect(MyProducer).to receive(:produce_batch).once.with(
        Deimos::Backends::Kafka,
        [
          hash_including({
            payload: { 'test_id' => 'foo', 'some_int' => 123 },
            topic: 'a-new-topic',
            headers: { 'foo' => 'bar' },
            partition_key: nil
          }),
          hash_including({
            payload: { 'test_id' => 'bar', 'some_int' => 124 },
            topic: 'a-new-topic',
            headers: { 'foo' => 'bar' },
            partition_key: nil
          })
        ]
      ).and_call_original

      MyProducer.publish_list(
        [{ 'test_id' => 'foo', 'some_int' => 123 },
         { 'test_id' => 'bar', 'some_int' => 124 }],
        topic: 'a-new-topic',
        headers: { 'foo' => 'bar' }
      )
      expect('a-new-topic').to have_sent({ 'test_id' => 'foo', 'some_int' => 123 }, nil, nil, { 'foo' => 'bar' })
      expect('my-topic').not_to have_sent('test_id' => 'foo', 'some_int' => 123)
      expect('my-topic').not_to have_sent('test_id' => 'foo2', 'some_int' => 123)
    end

    it 'should add a message ID' do
      payload = { 'test_id' => 'foo',
                  'some_int' => 123,
                  'message_id' => a_kind_of(String),
                  'timestamp' => a_kind_of(String) }
      MyProducerWithID.publish_list(
        [{ 'test_id' => 'foo', 'some_int' => 123, :payload_key => 'key' }]
      )
      expect(MyProducerWithID.topic).to have_sent(payload, 'key', 'key')

    end

    it 'should not publish if publish disabled' do
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

      MyProducer.publish_list([payload])
      expect('prefix.my-topic').to have_sent(payload, 'foo', 'foo')
      expect(karafka.produced_messages.size).to eq(1)
      karafka.produced_messages.clear

      Deimos.configure { |c| c.producers.topic_prefix = nil }

      MyProducer.publish_list(
        [{ 'test_id' => 'foo', 'some_int' => 123 }]
      )
      expect('my-topic').to have_sent(payload, 'foo', 'foo')
      expect(karafka.produced_messages.size).to eq(1)
    end

    it 'should properly encode and coerce values with a nested record' do
      MyNestedSchemaProducer.publish({
        'test_id' => 'foo',
        'test_float' => BigDecimal('123.456'),
        'test_array' => ['1'],
        'some_nested_record' => {
          'some_int' => 123,
          'some_float' => BigDecimal('456.789'),
          'some_string' => '123',
          'some_optional_int' => nil
        },
        'some_optional_record' => nil
                                     })
      expect(MyNestedSchemaProducer.topic).to have_sent(
        'test_id' => 'foo',
        'test_float' => 123.456,
        'test_array' => ['1'],
        'some_nested_record' => {
          'some_int' => 123,
          'some_float' => 456.789,
          'some_string' => '123',
          'some_optional_int' => nil
        },
        'some_optional_record' => nil
      )
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

    describe 'payload logging' do
      context 'with default / full' do
        it 'should log full payload' do
          allow(Karafka.logger).to receive(:info)
          MyProducerWithID.publish_list(
            [
              { 'test_id' => 'foo', 'some_int' => 123, :payload_key => 'key' },
              { 'test_id' => 'foo2', 'some_int' => 123, :payload_key => 'key2' },
            ]
          )
          expect(Karafka.logger).to have_received(:info).with(match_message({
            message: 'Publishing Messages for my-topic-with-id:',
            payloads: [
              {
                payload: { 'test_id' => 'foo', 'some_int' => 123 },
                key: 'key'
              },
              {
                payload: { 'test_id' => 'foo2', 'some_int' => 123 },
                key: 'key2'
              }
            ]
          }))
        end
      end

      context 'with count' do
        it 'should log only count' do
          Deimos.karafka_config_for(topic: 'my-topic-with-id').payload_log :count
          allow(Karafka.logger).to receive(:info)
          MyProducerWithID.publish_list(
            [
              { 'test_id' => 'foo', 'some_int' => 123, :payload_key => 'key' },
              { 'test_id' => 'foo2', 'some_int' => 123, :payload_key => 'key' }
            ]
          )
          expect(Karafka.logger).to have_received(:info).with(match_message({
            message: 'Publishing Messages for my-topic-with-id:',
            payloads_count: 2
          }))
        end
      end
    end

    context 'with Schema Class payloads' do
      it 'should fail on invalid message with error handler' do
        expect(Deimos::ProducerMiddleware).to receive(:call).and_raise('OH NOES')
        expect { MyProducer.publish(Schemas::MyNamespace::MySchema.new(test_id: 'foo', some_int: 'invalid')) }.
          to raise_error('OH NOES')
      end

      it 'should produce a message' do
        expect(MyProducer).to receive(:produce_batch).once.with(
          Deimos::Backends::Kafka,
          [
            hash_including({
              payload: { 'test_id' => 'foo', 'some_int' => 123, 'payload_key' => nil },
              topic: 'my-topic',
              partition_key: nil,
            }),
            hash_including({
              payload: { 'test_id' => 'bar', 'some_int' => 124, 'payload_key' => nil },
              topic: 'my-topic',
              partition_key: nil
            })
          ]
        ).and_call_original

        MyProducer.publish_list(
          [Schemas::MyNamespace::MySchema.new(test_id: 'foo', some_int: 123),
           Schemas::MyNamespace::MySchema.new(test_id: 'bar', some_int: 124)]
        )
        expect('my-topic').to have_sent('test_id' => 'foo', 'some_int' => 123)
        expect('your-topic').not_to have_sent('test_id' => 'foo', 'some_int' => 123)
        expect('my-topic').not_to have_sent('test_id' => 'foo2', 'some_int' => 123)
      end

      it 'should not publish if publish disabled' do
        expect(MyProducer).not_to receive(:produce_batch)
        Deimos.configure { |c| c.producers.disabled = true }
        MyProducer.publish_list(
          [Schemas::MyNamespace::MySchema.new(test_id: 'foo', some_int: 123),
           Schemas::MyNamespace::MySchema.new(test_id: 'bar', some_int: 124)]
        )
        expect(MyProducer.topic).not_to have_sent(anything)
      end

      it 'should encode the key' do
        Deimos.configure { |c| c.producers.topic_prefix = nil }

        MyProducer.publish_list(
          [Schemas::MyNamespace::MySchema.new(test_id: 'foo', some_int: 123),
           Schemas::MyNamespace::MySchema.new(test_id: 'bar', some_int: 124)]
        )
      end

      it 'should encode with a schema' do
        MySchemaProducer.publish_list(
          [Schemas::MyNamespace::MySchema.new(test_id: 'foo', some_int: 123, payload_key: { 'test_id' => 'foo_key' }),
           Schemas::MyNamespace::MySchema.new(test_id: 'bar', some_int: 124, payload_key: { 'test_id' => 'bar_key' })]
        )
      end

      it 'should properly encode and coerce values with a nested record' do
        MyNestedSchemaProducer.publish(
          Schemas::MyNamespace::MyNestedSchema.new(
            test_id: 'foo',
            test_float: BigDecimal('123.456'),
            test_array: ['1'],
            some_nested_record: Schemas::MyNamespace::MyNestedSchema::MyNestedRecord.new(
              some_int: 123,
              some_float: BigDecimal('456.789'),
              some_string: '123',
              some_optional_int: nil
            ),
            some_optional_record: nil
          )
        )
        expect(MyNestedSchemaProducer.topic).to have_sent(
          'test_id' => 'foo',
          'test_float' => 123.456,
          'test_array' => ['1'],
          'some_nested_record' => {
            'some_int' => 123,
            'some_float' => 456.789,
            'some_string' => '123',
            'some_optional_int' => nil
          },
          'some_optional_record' => nil
        )
      end
    end

    describe 'disabling' do
      it 'should disable globally' do
        Deimos.disable_producers do
          Deimos.disable_producers do # test nested
            MyProducer.publish({
              'test_id' => 'foo',
              'some_int' => 123,
              :payload_key => '123'
                               })
            MyProducerWithID.publish({
              'test_id' => 'foo', 'some_int' => 123
                                     })
            expect('my-topic').not_to have_sent(anything)
            expect(Deimos).to be_producers_disabled
            expect(Deimos).to be_producers_disabled([MyProducer])
          end
        end

        MyProducerWithID.publish({
          'test_id' => 'foo', 'some_int' => 123, :payload_key => 123
                                 })
        expect('my-topic-with-id').
          to have_sent('test_id' => 'foo', 'some_int' => 123,
                       'message_id' => anything, 'timestamp' => anything)
        expect(Deimos).not_to be_producers_disabled
        expect(Deimos).not_to be_producers_disabled([MyProducer])
      end

      it 'should disable a single producer' do
        Deimos.disable_producers(MyProducer) do # test nested
          Deimos.disable_producers(MyProducer) do
            MySchemaProducer.publish({
                                       'test_id' => 'foo', 'some_int' => 123,
                                       :payload_key => { 'test_id' => 'foo_key' }
                                     })
            MyProducer.publish({
                                 'test_id' => 'foo',
                                 'some_int' => 123,
                                 :payload_key => '123'
                               })
            expect('my-topic').not_to have_sent(anything)
            expect('my-topic-schema').to have_sent('test_id' => 'foo', 'some_int' => 123)
            expect(Deimos).not_to be_producers_disabled
            expect(Deimos).to be_producers_disabled(MyProducer)
            expect(Deimos).not_to be_producers_disabled(MySchemaProducer)
          end
        end
        expect(Deimos).not_to be_producers_disabled
        expect(Deimos).not_to be_producers_disabled(MyProducer)
        expect(Deimos).not_to be_producers_disabled(MySchemaProducer)
        MyProducer.publish({
                             'test_id' => 'foo',
                             'some_int' => 123,
                             :payload_key => '123'
                           })
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
        Deimos.configure { producers.backend = :outbox }
        expect(described_class.determine_backend_class(true, false)).
          to eq(Deimos::Backends::Outbox)
        expect(described_class.determine_backend_class(false, false)).
          to eq(Deimos::Backends::Outbox)
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
