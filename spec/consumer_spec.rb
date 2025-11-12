# frozen_string_literal: true

require 'rails/generators'

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
          messages.payloads.first&.to_h&.dig(:test_id) == ['fatal']
        end

        # :nodoc:
        def consume_message(message)
          message.payload
          message.key
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
          reraise_errors true
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
              config.schema.schema_namespace_map = {
                'com' => 'Schemas',
                'com.my-namespace.my-suborg' => %w(Schemas MyNamespace)
              }
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
            test_consume_message(MyConsumer, nil, key: 'foo') do |message|
              expect(message).to be_nil
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

          it 'should work if schema is set to string' do
            Karafka::App.routes.redraw do
              topic 'my_consume_topic' do
                schema 'MySchema'
                namespace 'com.my-namespace'
                key_config plain: true
                consumer MyConsumer
                reraise_errors true
                use_schema_classes use_schema_classes
                reraise_errors true
              end
            end

            test_consume_message(MyConsumer, { 'test_id' => 'foo',
                                 'some_int' => 123 }, key: 'a key')
          end

          it 'should fail if reraise is false but fatal_error is true' do
            expect { test_consume_message(MyConsumer, { test_id: 'fatal' }) }.
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
            expect {
              test_consume_message(MyConsumer,
                                   { 'test_id' => 'foo',
                                   'some_int' => 123,
                                   'extra_field' => 'field name' })
            }.
              to raise_error(Avro::SchemaValidator::ValidationError)
          end

          it 'should not fail when before_consume fails without reraising errors' do
            set_karafka_config(:reraise_errors, false)
            expect {
              test_consume_message(
                MyConsumer,
                { 'test_id' => 'foo',
                  'some_int' => 123 }
              ) { raise 'OH NOES' }
            }.not_to raise_error
          end

          it 'should not fail when consume fails without reraising errors' do
            set_karafka_config(:reraise_errors, false)
            allow(Deimos::ProducerMiddleware).to receive(:call) { |m| m[:payload] = m[:payload].to_json; m }
            expect {
              test_consume_message(
                MyConsumer,
                { 'invalid' => 'key' }
              )
            }.not_to raise_error
          end
        end
      end

      context 'with overridden schema classes' do

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
              reraise_errors true
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

      context 'with backwards compatible schema classes' do
        before(:each) do
          set_karafka_config(:use_schema_classes, true)
          Deimos.configure do |config|
            config.schema.use_full_namespace = true
            config.schema.schema_namespace_map = {
              'com' => 'Schemas',
              'com.my-namespace.my-suborg' => %w(Schemas MyNamespace)
            }
          end
          # update the Avro to include a new field
          generator.insert_into_file(schema_file, additional_field_json, after: '"fields": [', force: true)

          Karafka::App.routes.redraw do
            topic 'my_consume_topic' do
              schema 'MyNestedSchema'
              namespace 'com.my-namespace'
              key_config field: 'test_id'
              consumer ConsumerTest::MyConsumer
              reraise_errors true
              use_schema_classes true
              reraise_errors true
            end
          end
        end

        after(:each) do
          generator.gsub_file(schema_file, additional_field_json, '')
        end

        let(:generator) { Rails::Generators::Base.new }
        let(:schema_file) { File.join(__dir__, 'schemas/com/my-namespace/MyNestedSchema.avsc') }
        let(:additional_field_json) do
          '{"name": "additional_field", "type": "string", "default": ""},'
        end

        it 'should consume correctly and ignore the additional field' do
          test_consume_message('my_consume_topic',
                               { 'test_id' => 'foo',
                                 'test_float' => 4.0,
                                 'test_array' => %w(1 2),
                                 'additional_field' => 'bar',
                                 'some_nested_record' => {
                                   'some_int' => 1,
                                    'some_float' => 10.0,
                                    'some_string' => 'hi mom',
                                    'additional_field' => 'baz'
                                 } }) do |payload, _metadata|
            expect(payload['test_id']).to eq('foo')
            expect(payload['test_float']).to eq(4.0)
            expect(payload['some_nested_record']['some_int']).to eq(1)
            expect(payload.to_h).not_to have_key('additional_field')
            expect(payload.to_h['some_nested_record']).not_to have_key('additional_field')
                                 end

        end
      end

    end
  end
end

# rubocop:enable Metrics/ModuleLength
