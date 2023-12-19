# frozen_string_literal: true

require 'date'

# Wrapped in a module to prevent class leakage
# rubocop:disable Metrics/ModuleLength
module ActiveRecordConsumerTest
  describe Deimos::ActiveRecordConsumer, 'Message Consumer' do
    before(:all) do
      ActiveRecord::Base.connection.create_table(:widgets, force: true) do |t|
        t.string(:test_id)
        t.integer(:some_int)
        t.boolean(:some_bool)
        t.datetime(:some_datetime_int)
        t.timestamps
      end

      # :nodoc:
      class Widget < ActiveRecord::Base
        default_scope -> { where(some_bool: false) }
      end
      Widget.reset_column_information
    end

    before(:each) do
      Widget.delete_all
    end

    after(:all) do
      ActiveRecord::Base.connection.drop_table(:widgets)
    end

    prepend_before(:each) do

      consumer_class = Class.new(Deimos::ActiveRecordConsumer) do
        schema 'MySchemaWithDateTimes'
        namespace 'com.my-namespace'
        key_config plain: true
        record_class Widget
      end
      stub_const('MyConsumer', consumer_class)

      consumer_class = Class.new(Deimos::ActiveRecordConsumer) do
        schema 'MySchemaWithDateTimes'
        namespace 'com.my-namespace'
        key_config schema: 'MySchemaId_key'
        record_class Widget
      end
      stub_const('MyConsumerWithKey', consumer_class)

      consumer_class = Class.new(Deimos::ActiveRecordConsumer) do
        schema 'MySchema'
        namespace 'com.my-namespace'
        key_config none: true
        record_class Widget

        # :nodoc:
        def assign_key(_record, _payload, _key)
          # do nothing since we're not using primary keys
        end

        # :nodoc:
        def fetch_record(klass, payload, _key)
          klass.unscoped.where('test_id' => payload[:test_id]).first
        end
      end
      stub_const('MyCustomFetchConsumer', consumer_class)

      Time.zone = 'Eastern Time (US & Canada)'

      schema_class = Class.new(Deimos::SchemaClass::Record) do
        def schema
          'MySchema'
        end

        def namespace
          'com.my-namespace'
        end

        attr_accessor :test_id
        attr_accessor :some_int

        def initialize(test_id: nil,
                       some_int: nil)
          self.test_id = test_id
          self.some_int = some_int
        end

        def as_json(_opts={})
          {
            'test_id' => @test_id,
            'some_int' => @some_int,
            'payload_key' => @payload_key&.as_json
          }
        end
      end
      stub_const('Schemas::MySchema', schema_class)

      schema_datetime_class = Class.new(Deimos::SchemaClass::Record) do
        def schema
          'MySchemaWithDateTimes'
        end

        def namespace
          'com.my-namespace'
        end

        attr_accessor :test_id
        attr_accessor :some_int
        attr_accessor :updated_at
        attr_accessor :some_datetime_int
        attr_accessor :timestamp

        def initialize(test_id: nil,
                       some_int: nil,
                       updated_at: nil,
                       some_datetime_int: nil,
                       timestamp: nil)
          self.test_id = test_id
          self.some_int = some_int
          self.updated_at = updated_at
          self.some_datetime_int = some_datetime_int
          self.timestamp = timestamp
        end

        def as_json(_opts={})
          {
            'test_id' => @test_id,
            'some_int' => @some_int,
            'updated_at' => @updated_at,
            'some_datetime_int' => @some_datetime_int,
            'timestamp' => @timestamp,
            'payload_key' => @payload_key&.as_json
          }
        end
      end
      stub_const('Schemas::MySchemaWithDateTimes', schema_datetime_class)
    end

    describe 'consume' do
      SCHEMA_CLASS_SETTINGS.each do |setting, use_schema_classes|
        context "with Schema Class consumption #{setting}" do
          before(:each) do
            Deimos.configure { |config| config.schema.use_schema_classes = use_schema_classes }
          end

          it 'should receive events correctly' do
            travel 1.day do
              expect(Widget.count).to eq(0)
              test_consume_message(MyConsumer, {
                                     test_id: 'abc',
                                     some_int: 3,
                                     updated_at: 1.day.ago.to_i,
                                     some_datetime_int: Time.zone.now.to_i,
                                     timestamp: 2.minutes.ago.to_s
                                   }, call_original: true, key: 5)

              expect(Widget.count).to eq(1)
              widget = Widget.last
              expect(widget.id).to eq(5)
              expect(widget.test_id).to eq('abc')
              expect(widget.some_int).to eq(3)
              expect(widget.some_datetime_int).to eq(Time.zone.now)
              expect(widget.some_bool).to eq(false)
              expect(widget.updated_at).to eq(Time.zone.now)

              # test unscoped
              widget.update_attribute(:some_bool, true)

              # test update
              test_consume_message(MyConsumer, {
                                     test_id: 'abcd',
                                     some_int: 3,
                                     some_datetime_int: Time.zone.now.to_i,
                                     timestamp: 2.minutes.ago.to_s
                                   }, call_original: true, key: 5)
              expect(Widget.unscoped.count).to eq(1)
              widget = Widget.unscoped.last
              expect(widget.id).to eq(5)
              expect(widget.test_id).to eq('abcd')
              expect(widget.some_int).to eq(3)

              # test delete
              test_consume_message(MyConsumer, nil, call_original: true, key: 5)
              expect(Widget.count).to eq(0)

            end

          end

          it 'should update only updated_at' do
            travel_to Time.local(2020, 5, 5, 5, 5, 5)
            widget1 = Widget.create!(test_id: 'id1', some_int: 3)
            expect(widget1.updated_at.in_time_zone).to eq(Time.local(2020, 5, 5, 5, 5, 5))

            travel 1.day
            test_consume_message(MyCustomFetchConsumer, {
                                   test_id: 'id1',
                                   some_int: 3
                                 }, call_original: true)
            expect(widget1.reload.updated_at.in_time_zone).
              to eq(Time.local(2020, 5, 6, 5, 5, 5))
            travel_back
          end

          it 'should find widgets with a schema key' do
            widget1 = Widget.create!(test_id: 'id1')
            expect(widget1.some_int).to be_nil
            test_consume_message(MyConsumerWithKey, {
                                   test_id: 'id1',
                                   some_int: 3
                                 },
                                 key: { id: widget1.id },
                                 call_original: true)
            expect(widget1.reload.some_int).to eq(3)
            expect(Widget.count).to eq(1)
          end

          it 'should find widgets by custom logic' do
            widget1 = Widget.create!(test_id: 'id1')
            expect(widget1.some_int).to be_nil
            test_consume_message(MyCustomFetchConsumer, {
                                   test_id: 'id1',
                                   some_int: 3
                                 }, call_original: true)
            expect(widget1.reload.some_int).to eq(3)
            expect(Widget.count).to eq(1)
            test_consume_message(MyCustomFetchConsumer, {
                                   test_id: 'id2',
                                   some_int: 4
                                 }, call_original: true)
            expect(Widget.count).to eq(2)
            expect(Widget.find_by_test_id('id1').some_int).to eq(3)
            expect(Widget.find_by_test_id('id2').some_int).to eq(4)
          end

          it 'should not create record of process_message returns false' do
            allow_any_instance_of(MyConsumer).to receive(:process_message?).and_return(false)
            expect(Widget.count).to eq(0)
            test_consume_message(MyConsumer, {
                                   test_id: 'abc',
                                   some_int: 3,
                                   updated_at: 1.day.ago.to_i,
                                   some_datetime_int: Time.zone.now.to_i,
                                   timestamp: 2.minutes.ago.to_s
                                 }, call_original: true, key: 5)
            expect(Widget.count).to eq(0)
          end
        end
      end
    end
  end
end
# rubocop:enable Metrics/ModuleLength
