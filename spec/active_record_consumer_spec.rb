# frozen_string_literal: true

require 'date'

# :nodoc:
module ActiveRecordProducerTest
  describe Deimos::ActiveRecordConsumer do

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

    after(:all) do
      ActiveRecord::Base.connection.drop_table(:widgets)
    end

    prepend_before(:each) do

      consumer_class = Class.new(described_class) do
        schema 'MySchemaWithDateTimes'
        namespace 'com.my-namespace'
        key_config plain: true
        record_class Widget
      end
      stub_const('MyConsumer', consumer_class)

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

  end
end
