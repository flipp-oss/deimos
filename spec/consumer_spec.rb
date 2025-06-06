# frozen_string_literal: true

# :nodoc:
# rubocop:disable Metrics/ModuleLength
module ConsumerTest
  describe Deimos::Consumer, 'Message Consumer' do
    let(:use_schema_classes) { false }
    let(:reraise_errors) { false }
    prepend_before(:each) do
      # :nodoc:
      consumer_class = Class.new(described_class) do

        # :nodoc:
        def fatal_error?(_exception, messages)
          messages.payloads.first&.dig(:test_id) == ['fatal']
        end

        # :nodoc:
        def consume_message(message)
          message.payload
        end
      end
      stub_const('ConsumerTest::MyConsumer', consumer_class)
      route_usc = use_schema_classes
      route_rre = reraise_errors
      Karafka::App.routes.redraw do
        topic 'my_consume_topic' do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config field: 'test_id'
          consumer consumer_class
          use_schema_classes route_usc
          reraise_errors route_rre
        end
      end
    end

    describe 'consume' do
      SCHEMA_CLASS_SETTINGS.each do |setting, use_schema_classes|
        let(:use_schema_classes) { use_schema_classes }
        context "with Schema Class consumption #{setting}" do

          before(:each) do
            Deimos.configure do |config|
              config.schema.use_full_namespace = true
            end
          end

          it 'should consume a message' do
            test_consume_message(MyConsumer,
                                 { 'test_id' => 'foo',
                                 'some_int' => 123 }) do |payload, _metadata|
                                   expect(payload['test_id']).to eq('foo')
                                   expect(payload['some_int']).to eq(123)
                                 end
          end

          it 'should consume a nil message' do
            test_consume_message(MyConsumer, nil, key: 'foo') do
              expect(messages).to be_empty
            end
          end

          it 'should consume a message on a topic' do
            test_consume_message('my_consume_topic',
                                 { 'test_id' => 'foo',
                                 'some_int' => 123 }) do |payload, _metadata|
                                   expect(payload['test_id']).to eq('foo')
                                   expect(payload['some_int']).to eq(123)
                                 end
          end

          it 'should fail on invalid message' do
            expect { test_consume_message(MyConsumer, { 'invalid' => 'key' }) }.
              to raise_error(Avro::SchemaValidator::ValidationError)
          end

          it 'should fail if reraise is false but fatal_error is true' do
            expect { test_consume_message(MyConsumer, {test_id: 'fatal'}) }.
              to raise_error(Avro::SchemaValidator::ValidationError)
          end

          it 'should fail if fatal_error is true globally' do
            set_karafka_config(:fatal_error, proc { true })
            expect { test_consume_message(MyConsumer, { 'invalid' => 'key' }) }.
              to raise_error(Avro::SchemaValidator::ValidationError)
          end

          it 'should fail on message with extra fields' do
            allow_any_instance_of(Deimos::SchemaBackends::AvroValidation).
              to receive(:coerce) { |_, m| m.with_indifferent_access }
            expect { test_consume_message(MyConsumer,
                                         { 'test_id' => 'foo',
                                         'some_int' => 123,
                                         'extra_field' => 'field name' }) }.
              to raise_error(Avro::SchemaValidator::ValidationError)
          end

          it 'should not fail when before_consume fails without reraising errors' do
            set_karafka_config(:reraise_errors, false)
            expect {
              test_consume_message(
                MyConsumer,
                { 'test_id' => 'foo',
                  'some_int' => 123 }) { raise 'OH NOES' }
            }.not_to raise_error
          end

          it 'should not fail when consume fails without reraising errors' do
            set_karafka_config(:reraise_errors, false)
            allow(Deimos::ProducerMiddleware).to receive(:call) { |m| m[:payload] = m[:payload].to_json; m }
            expect {
              test_consume_message(
                MyConsumer,
                { 'invalid' => 'key' })
            }.not_to raise_error
          end
        end
      end

      context 'with overriden schema classes' do

        before(:each) do
          set_karafka_config(:use_schema_classes, true)
          Deimos.configure do |config|
            config.schema.use_full_namespace = true
          end
        end

        prepend_before(:each) do
          consumer_class = Class.new(described_class) do
            # :nodoc:
            def consume_message(message)
              message.payload
            end
          end
          stub_const('ConsumerTest::MyConsumer', consumer_class)
          Deimos.config.schema.use_schema_classes = true
          Karafka::App.routes.redraw do
            topic 'my_consume_topic' do
              schema 'MyUpdatedSchema'
              namespace 'com.my-namespace'
              key_config field: 'test_id'
              consumer consumer_class
            end
          end
        end
        after(:each) do
          Karafka::App.routes.clear
        end

        it 'should consume messages' do
          test_consume_message('my_consume_topic',
                               { 'test_id' => 'foo',
                                 'some_int' => 1 }) do |payload, _metadata|
            expect(payload['test_id']).to eq('foo')
            expect(payload['some_int']).to eq(1)
            expect(payload['super_int']).to eq(9000)
                                 end
        end

      end
    end

  end
end
# rubocop:enable Metrics/ModuleLength
