# frozen_string_literal: true

require 'date'

# Wrapped in a module to prevent class leakage
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
                             }, { call_original: true, key: 5 })

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
                             }, { call_original: true, key: 5 })
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
                           }, { call_original: true })
      expect(widget1.reload.updated_at.in_time_zone).
        to eq(Time.local(2020, 5, 6, 5, 5, 5))
      travel_back
    end

    it 'should find widgets by custom logic' do
      widget1 = Widget.create!(test_id: 'id1')
      expect(widget1.some_int).to be_nil
      test_consume_message(MyCustomFetchConsumer, {
                             test_id: 'id1',
                             some_int: 3
                           }, { call_original: true })
      expect(widget1.reload.some_int).to eq(3)
      expect(Widget.count).to eq(1)
      test_consume_message(MyCustomFetchConsumer, {
                             test_id: 'id2',
                             some_int: 4
                           }, { call_original: true })
      expect(Widget.count).to eq(2)
      expect(Widget.find_by_test_id('id1').some_int).to eq(3)
      expect(Widget.find_by_test_id('id2').some_int).to eq(4)
    end

    it 'should not create record of process_message returns false' do
      MyConsumer.stub(:process_message?).and_return(false)
      expect(Widget.count).to eq(0)
      test_consume_message(MyConsumer, {
                               test_id: 'abc',
                               some_int: 3,
                               updated_at: 1.day.ago.to_i,
                               some_datetime_int: Time.zone.now.to_i,
                               timestamp: 2.minutes.ago.to_s
                             }, { call_original: true, key: 5 })
      expect(Widget.count).to eq(0)
    end
  end
end
