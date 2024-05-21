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
        def fatal_error?(_exception, payload, _metadata)
          payload.to_s == 'fatal'
        end

        # :nodoc:
        def consume_message(_payload, _metadata)
        end
      end
      stub_const('ConsumerTest::MyConsumer', consumer_class)
      route_usc = use_schema_classes
      route_rre = reraise_errors
      Karafka::App.routes.redraw do
        schema 'MySchema'
        namespace 'com.my-namespace'
        key_config field: 'test_id'
        consumer consumer_class
        use_schema_classes route_usc
        reraise_errors route_rre
      end
    end

    describe 'consume' do
      SCHEMA_CLASS_SETTINGS.each do |setting, use_schema_classes|
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
            test_consume_message(MyConsumer, nil) do |payload, _metadata|
              expect(payload).to be_nil
            end
          end

          it 'should consume a message idempotently' do
            # testing for a crash and re-consuming the same message/metadata
            key = { 'test_id' => 'foo' }
            test_metadata = { key: key }
            allow_any_instance_of(MyConsumer).to(receive(:decode_key)) do |_instance, k|
              k['test_id']
            end
            MyConsumer.new.around_consume({ 'test_id' => 'foo',
                                            'some_int' => 123 }, test_metadata) do |_payload, metadata|
                                              expect(metadata[:key]).to eq('foo')
                                            end
            MyConsumer.new.around_consume({ 'test_id' => 'foo',
                                            'some_int' => 123 }, test_metadata) do |_payload, metadata|
                                              expect(metadata[:key]).to eq('foo')
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
            expect { test_consume_message(MyConsumer, { 'invalid' => 'key' }) }.to raise_error('')
          end

          it 'should fail if reraise is false but fatal_error is true' do
            expect { test_consume_message(MyConsumer, 'fatal') }.to raise_error('')
          end

          it 'should fail if fatal_error is true globally' do
            set_karafka_config(:fatal_error, proc { true })
            test_consume_message(MyConsumer, { 'invalid' => 'key' })
          end

          it 'should fail on message with extra fields' do
            test_consume_invalid_message(MyConsumer,
                                         { 'test_id' => 'foo',
                                         'some_int' => 123,
                                         'extra_field' => 'field name' })
          end

          it 'should not fail when before_consume fails without reraising errors' do
            set_karafka_config(:reraise_errors, false)
            expect {
              test_consume_message(
                MyConsumer,
                { 'test_id' => 'foo',
                  'some_int' => 123 },
                skip_expectation: true
              ) { raise 'OH NOES' }
            }.not_to raise_error
          end

          it 'should not fail when consume fails without reraising errors' do
            set_karafka_config(:reraise_errors, false)
            expect {
              test_consume_message(
                MyConsumer,
                { 'invalid' => 'key' },
                skip_expectation: true
              )
            }.not_to raise_error
          end

          it 'should call original' do
            expect {
              test_consume_message(MyConsumer,
                                   { 'test_id' => 'foo', 'some_int' => 123 },
                                   call_original: true)
            }.to raise_error('This should not be called unless call_original is set')
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
            def consume(_payload, _metadata)
            end
          end
          stub_const('ConsumerTest::MyConsumer', consumer_class)
          Karafka::App.routes.redraw do
            schema 'MyUpdatedSchema'
            namespace 'com.my-namespace'
            key_config field: 'test_id'
            consumer consumer_class
          end
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

    describe 'decode_key' do

      it 'should use the key field in the value if set' do
        # actual decoding is disabled in test
        expect(MyConsumer.new.decode_key('test_id' => '123')).to eq('123')
        expect { MyConsumer.new.decode_key(123) }.to raise_error(NoMethodError)
      end

      it 'should use the key schema if set' do
        consumer_class = Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config schema: 'MySchema_key'
        end
        stub_const('ConsumerTest::MySchemaConsumer', consumer_class)
        expect(MyConsumer.new.decode_key('test_id' => '123')).to eq('123')
        expect { MyConsumer.new.decode_key(123) }.to raise_error(NoMethodError)
      end

      it 'should not decode if plain is set' do
        consumer_class = Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config plain: true
        end
        stub_const('ConsumerTest::MyNonEncodedConsumer', consumer_class)
        expect(MyNonEncodedConsumer.new.decode_key('123')).to eq('123')
      end

      it 'should error with nothing set' do
        consumer_class = Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
        end
        stub_const('ConsumerTest::MyErrorConsumer', consumer_class)
        expect { MyErrorConsumer.new.decode_key('123') }.
          to raise_error('No key config given - if you are not decoding keys, please use `key_config plain: true`')
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
          def consume(_payload, _metadata)
            raise 'This should not be called unless call_original is set'
          end
        end
        stub_const('ConsumerTest::MyConsumer', consumer_class)
      end

      it 'should consume a message' do
        expect(Deimos.config.metrics).to receive(:histogram).twice
        test_consume_message('my_consume_topic',
                             { 'test_id' => 'foo',
                             'some_int' => 123,
                             'updated_at' => Time.now.to_i,
                             'timestamp' => 2.minutes.ago.to_s }) do |payload, _metadata|
                               expect(payload['test_id']).to eq('foo')
                             end
      end

      it 'should fail nicely when timestamp wrong format' do
        expect(Deimos.config.metrics).to receive(:histogram).twice
        test_consume_message('my_consume_topic',
                             { 'test_id' => 'foo',
                             'some_int' => 123,
                             'updated_at' => Time.now.to_i,
                             'timestamp' => 'dffdf' }) do |payload, _metadata|
                               expect(payload['test_id']).to eq('foo')
                             end
        test_consume_message('my_consume_topic',
                             { 'test_id' => 'foo',
                             'some_int' => 123,
                             'updated_at' => Time.now.to_i,
                             'timestamp' => '' }) do |payload, _metadata|
                               expect(payload['test_id']).to eq('foo')
                             end
      end

    end
  end
end
# rubocop:enable Metrics/ModuleLength
