# frozen_string_literal: true

# :nodoc:
module ActiveRecordProducerTest
  describe Deimos::ActiveRecordProducer do

    before(:all) do
      ActiveRecord::Base.connection.create_table(:widgets) do |t|
        t.string(:test_id)
        t.integer(:some_int)
        t.boolean(:some_bool)
        t.timestamps
      end

      # :nodoc:
      class Widget < ActiveRecord::Base
        # @return [String]
        def generated_id
          'generated_id'
        end
      end
    end

    after(:all) do
      ActiveRecord::Base.connection.drop_table(:widgets)
    end

    prepend_before(:each) do

      producer_class = Class.new(Deimos::ActiveRecordProducer) do
        schema 'MySchema'
        namespace 'com.my-namespace'
        topic 'my-topic'
        key_config none: true
      end
      stub_const('MyProducer', producer_class)

      producer_class = Class.new(Deimos::ActiveRecordProducer) do
        schema 'MySchemaWithBooleans'
        namespace 'com.my-namespace'
        topic 'my-topic-with-boolean'
        key_config none: true
      end
      stub_const('MyBooleanProducer', producer_class)

      producer_class = Class.new(Deimos::ActiveRecordProducer) do
        schema 'MySchemaWithId'
        namespace 'com.my-namespace'
        topic 'my-topic-with-id'
        key_config none: true
        record_class Widget

        # :nodoc:
        def self.generate_payload(attrs, widget)
          super.merge(message_id: widget.generated_id)
        end

      end
      stub_const('MyProducerWithID', producer_class)

      producer_class = Class.new(Deimos::ActiveRecordProducer) do
        schema 'MySchemaWithUniqueId'
        namespace 'com.my-namespace'
        topic 'my-topic-with-unique-id'
        key_config field: :id
        record_class Widget
      end
      stub_const('MyProducerWithUniqueID', producer_class)
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
      MyProducerWithID.send_event(id: widget.id, test_id: 'abc2', some_int: 3)
      expect('my-topic-with-id').to have_sent(
        test_id: 'abc2',
        some_int: 3,
        message_id: 'generated_id',
        timestamp: anything
      )
    end

    specify '#watched_attributes' do
      expect(MyProducer.watched_attributes).to eq(%w(test_id some_int))
    end

  end
end
