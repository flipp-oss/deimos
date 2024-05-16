# frozen_string_literal: true

describe Deimos::ActiveRecordProducer do

  include_context 'with widgets'

  prepend_before(:each) do
    producer_class = Class.new(Deimos::ActiveRecordProducer)
    stub_const('MyProducer', producer_class)

    producer_class = Class.new(Deimos::ActiveRecordProducer)
    stub_const('MyBooleanProducer', producer_class)

    producer_class = Class.new(Deimos::ActiveRecordProducer) do
      record_class Widget

      # :nodoc:
      def self.generate_payload(attrs, widget)
        super.merge(message_id: widget.generated_id)
      end

    end
    stub_const('MyProducerWithID', producer_class)

    producer_class = Class.new(Deimos::ActiveRecordProducer) do
      record_class Widget
    end
    stub_const('MyProducerWithUniqueID', producer_class)

    producer_class = Class.new(Deimos::ActiveRecordProducer) do
      record_class Widget

      # :nodoc:
      def self.post_process(batch)
        batch.each do |message|
          message.test_id = 'post_processed'
          message.save!
        end
      end
    end

    stub_const('MyProducerWithPostProcess', producer_class)
    Karafka::App.routes.redraw do
      topic 'my-topic' do
        schema 'MySchema'
        namespace 'com.my-namespace'
        key_config none: true
        producer_class MyProducer
      end
      topic 'my-topic-with-boolean' do
        producer_class MyBooleanProducer
        schema 'MySchemaWithBooleans'
        namespace 'com.my-namespace'
        key_config none: true
      end
      topic 'my-topic-with-id' do
        schema 'MySchemaWithId'
        namespace 'com.my-namespace'
        key_config none: true
        producer_class MyProducerWithID
      end
      topic 'my-topic-with-unique-id' do
        schema 'MySchemaWithUniqueId'
        namespace 'com.my-namespace'
        key_config field: :id
        producer_class MyProducerWithUniqueID
      end
      topic 'my-topic-with-post-process' do
        schema 'MySchemaWithUniqueId'
        namespace 'com.my-namespace'
        key_config field: :id
        producer_class MyProducerWithPostProcess
      end
    end

  end

  describe 'produce' do
    SCHEMA_CLASS_SETTINGS.each do |setting, use_schema_classes|
      context "with Schema Class consumption #{setting}" do
        before(:each) do
          Deimos.configure do |config|
            config.schema.use_schema_classes = use_schema_classes
            config.schema.use_full_namespace = true
          end
        end

        it 'should send events correctly' do
          MyProducer.send_event(Widget.new(test_id: 'abc', some_int: 3))
          expect('my-topic').to have_sent(test_id: 'abc', some_int: 3)
        end

        it 'should coerce values' do
          MyProducer.send_event(Widget.new(test_id: 'abc', some_int: '3'))
          MyProducer.send_event(Widget.new(test_id: 'abc', some_int: 4.5))
          expect('my-topic').to have_sent(test_id: 'abc', some_int: 3)
          expect('my-topic').to have_sent(test_id: 'abc', some_int: 4)
          expect {
            MyProducer.send_event(Widget.new(test_id: 'abc', some_int: nil))
          }.to raise_error(Avro::SchemaValidator::ValidationError)

          MyBooleanProducer.send_event(Widget.new(test_id: 'abc', some_bool: nil))
          MyBooleanProducer.send_event(Widget.new(test_id: 'abc', some_bool: true))
          expect('my-topic-with-boolean').to have_sent(test_id: 'abc', some_bool: false)
          expect('my-topic-with-boolean').to have_sent(test_id: 'abc', some_bool: true)
        end

        it 'should be able to call the record' do
          widget = Widget.create!(test_id: 'abc2', some_int: 3)
          MyProducerWithID.send_event({id: widget.id, test_id: 'abc2', some_int: 3})
          expect('my-topic-with-id').to have_sent(
            test_id: 'abc2',
            some_int: 3,
            message_id: 'generated_id',
            timestamp: anything
          )
        end

        it 'should post process the batch of records in #send_events' do
          widget = Widget.create!(test_id: 'abc3', some_int: 4)
          MyProducerWithPostProcess.send_events([widget])
          expect(widget.reload.test_id).to eq('post_processed')
        end

      end
    end
  end

  specify '#watched_attributes' do
    expect(MyProducer.watched_attributes).to eq(%w(test_id some_int))
  end

end
