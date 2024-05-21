# frozen_string_literal: true

require 'deimos/utils/db_poller'

# rubocop:disable Layout/LineLength

# @param secs [Integer]
# @param mins [Integer]
# @return [Time]
def time_value(secs: 0, mins: 0)
  Time.local(2015, 5, 5, 1, 0, 0) + (secs + (mins * 60))
end

each_db_config(Deimos::Utils::DbPoller::Base) do

  before(:each) do
    Deimos::PollInfo.delete_all
  end

  describe '#start!' do

    before(:each) do
      producer_class = Class.new(Deimos::Producer)
      stub_const('MyProducer', producer_class)

      producer_class = Class.new(Deimos::Producer)
      stub_const('MyProducerWithID', producer_class)

      Karafka::App.routes.redraw do
        topic 'my-topic' do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config field: 'test_id'
          producer_class MyProducer
        end
        topic 'my-topic-with-id' do
          schema 'MySchemaWithId'
          namespace 'com.my-namespace'
          key_config plain: true
          producer_class MyProducerWithID
        end
      end

    end

    it 'should raise an error if no pollers configured' do
      Deimos.configure {}
      expect { Deimos::Utils::DbPoller.start! }.to raise_error('No pollers configured!')
    end

    it 'should start pollers as configured' do
      Deimos.configure do
        db_poller do
          producer_class 'MyProducer'
        end
        db_poller do
          producer_class 'MyProducerWithID'
        end
      end

      allow(Deimos::Utils::DbPoller::TimeBased).to receive(:new)
      signal_double = instance_double(Sigurd::SignalHandler, run!: nil)
      allow(Sigurd::SignalHandler).to receive(:new).and_return(signal_double)
      Deimos::Utils::DbPoller.start!
      expect(Deimos::Utils::DbPoller::TimeBased).to have_received(:new).twice
      expect(Deimos::Utils::DbPoller::TimeBased).to have_received(:new).
        with(Deimos.config.db_poller_objects[0])
      expect(Deimos::Utils::DbPoller::TimeBased).to have_received(:new).
        with(Deimos.config.db_poller_objects[1])
    end
  end

  describe 'pollers' do
    include_context 'with widgets'

    let(:poller) do
      poller = Deimos::Utils::DbPoller.class_for_config(config).new(config)
      allow(poller).to receive(:sleep)
      poller
    end

    let(:config) { Deimos.config.db_poller_objects.first.dup }

    before(:each) do
      producer_class = Class.new(Deimos::ActiveRecordProducer) do
        record_class Widget

        # :nodoc:
        def self.generate_payload(attrs, widget)
          super.merge(message_id: widget.generated_id)
        end
      end
      stub_const('MyProducer', producer_class)

      Widget.delete_all
      Karafka::App.routes.redraw do
        topic 'my-topic-with-id' do
          schema 'MySchemaWithId'
          namespace 'com.my-namespace'
          key_config none: true
          producer_class MyProducer
        end
      end

      Deimos.configure do
        db_poller do
          producer_class 'MyProducer'
          run_every 1.minute
        end
      end
    end

    after(:each) do
      travel_back
    end

    it 'should crash if initialized with an invalid producer' do
      config.producer_class = 'NoProducer'
      expect { described_class.new(config) }.to raise_error('Class NoProducer not found!')
    end

    describe '#retrieve_poll_info' do

      it 'should start from beginning when configured' do
        poller.retrieve_poll_info
        expect(Deimos::PollInfo.count).to eq(1)
        info = Deimos::PollInfo.last
        expect(info.producer).to eq('MyProducer')
        expect(info.last_sent).to eq(Time.new(0))
        expect(info.last_sent_id).to eq(0)
      end

      it 'should start from now when configured' do
        travel_to time_value
        config.start_from_beginning = false
        poller.retrieve_poll_info
        expect(Deimos::PollInfo.count).to eq(1)
        info = Deimos::PollInfo.last
        expect(info.producer).to eq('MyProducer')
        expect(info.last_sent).to eq(time_value)
        expect(info.last_sent_id).to eq(0)
      end

    end

    specify '#start' do
      i = 0
      expect(poller).to receive(:process_updates).twice do
        i += 1
        poller.stop if i == 2
      end
      poller.start
    end

    specify '#should_run?' do
      Deimos::PollInfo.create!(producer: 'MyProducer',
                               last_sent: time_value)
      poller.retrieve_poll_info

      # run_every is set to 1 minute
      travel_to time_value(secs: 62)
      expect(poller.should_run?).to eq(true)

      travel_to time_value(secs: 30)
      expect(poller.should_run?).to eq(false)

      travel_to time_value(mins: -1) # this shouldn't be possible but meh
      expect(poller.should_run?).to eq(false)

      # take the 2 seconds of delay_time into account
      travel_to time_value(secs: 60)
      expect(poller.should_run?).to eq(false)
    end

    describe '#process_batch' do
      let(:widgets) { (1..3).map { Widget.create!(test_id: 'some_id', some_int: 4) } }
      let(:status) { Deimos::Utils::DbPoller::PollStatus.new(0, 0, 0) }

      before(:each) do
        allow(Deimos.config.tracer).to receive(:start).and_return('a span')
        allow(Deimos.config.tracer).to receive(:set_error)
        allow(Deimos.config.tracer).to receive(:finish)
      end

      it 'should process the batch' do
        travel_to time_value
        widgets.last.update_attribute(:updated_at, time_value(mins: -30))
        expect(MyProducer).to receive(:send_events).with(widgets)
        poller.retrieve_poll_info
        poller.process_and_touch_info(widgets, status)
        info = Deimos::PollInfo.last
        expect(info.last_sent.in_time_zone).to eq(time_value(mins: -30))
        expect(info.last_sent_id).to eq(widgets.last.id)
      end

      it 'should create a span' do
        poller.retrieve_poll_info
        poller.process_batch_with_span(widgets, status)
        expect(status.batches_errored).to eq(0)
        expect(status.batches_processed).to eq(1)
        expect(status.messages_processed).to eq(3)
        expect(Deimos.config.tracer).to have_received(:finish).with('a span')
      end

      context 'with skip_too_large_messages on' do
        before(:each) { config.skip_too_large_messages = true }

        it 'should skip and move on' do
          rdkafka_error = instance_double(Rdkafka::RdkafkaError, code: :msg_size_too_large)
          error = WaterDrop::Errors::ProduceManyError.new(nil, nil)
          allow(error).to receive(:cause).and_return(rdkafka_error)
          allow(poller).to receive(:sleep)
          allow(poller).to receive(:process_batch) do
            raise error
          end
          poller.retrieve_poll_info
          poller.process_batch_with_span(widgets, status)
          expect(poller).not_to have_received(:sleep)
          expect(Deimos.config.tracer).to have_received(:set_error).with('a span', error)
          expect(status.batches_errored).to eq(1)
          expect(status.batches_processed).to eq(0)
          expect(status.messages_processed).to eq(3)

        end
      end

      context 'with skip_too_large_messages off' do
        it 'should retry forever' do
          called_once = false
          allow(poller).to receive(:sleep)
          allow(poller).to receive(:process_batch) do
            unless called_once
              called_once = true
              raise Kafka::MessageSizeTooLarge, 'OH NOES'
            end
          end
          poller.retrieve_poll_info
          poller.process_batch_with_span(widgets, status)
          expect(poller).to have_received(:sleep).once.with(0.5)
          expect(Deimos.config.tracer).to have_received(:finish).with('a span')
          expect(status.batches_errored).to eq(0)
          expect(status.batches_processed).to eq(1)
          expect(status.messages_processed).to eq(3)

        end

      end

      it 'should retry on Kafka error' do
        called_once = false
        allow(poller).to receive(:sleep)
        allow(poller).to receive(:process_batch) do
          unless called_once
            called_once = true
            raise Kafka::Error, 'OH NOES'
          end
        end
        poller.retrieve_poll_info
        poller.process_batch_with_span(widgets, status)
        expect(poller).to have_received(:sleep).once.with(0.5)
        expect(Deimos.config.tracer).to have_received(:finish).with('a span')
        expect(status.batches_errored).to eq(0)
        expect(status.batches_processed).to eq(1)
        expect(status.messages_processed).to eq(3)
      end

      it 'should retry only once on other errors' do
        error = RuntimeError.new('OH NOES')
        allow(poller).to receive(:sleep)
        allow(poller).to receive(:process_batch).and_raise(error)
        poller.retrieve_poll_info
        poller.process_batch_with_span(widgets, status)
        expect(poller).to have_received(:sleep).once.with(0.5)
        expect(Deimos.config.tracer).to have_received(:set_error).with('a span', error)
        expect(status.batches_errored).to eq(1)
        expect(status.batches_processed).to eq(0)
        expect(status.messages_processed).to eq(3)
      end
    end

    describe '#process_updates' do
      before(:each) do
        Deimos::PollInfo.create!(producer: 'MyProducer',
                                 last_sent: time_value(mins: -61),
                                 last_sent_id: 0)
        poller.retrieve_poll_info
        travel_to time_value
        stub_const('Deimos::Utils::DbPoller::BATCH_SIZE', 3)
      end

      let!(:old_widget) do
        # old widget, earlier than window
        Widget.create!(test_id: 'some_id', some_int: 40,
                       updated_at: time_value(mins: -200))
      end

      let!(:last_widget) do
        # new widget, before delay
        Widget.create!(test_id: 'some_id', some_int: 10,
                       updated_at: time_value(secs: -1))
      end

      let!(:widgets) do
        (1..7).map do |i|
          Widget.create!(test_id: 'some_id', some_int: i,
                         updated_at: time_value(mins: -61, secs: 30 + i))
        end
      end

      it 'should update the full table' do
        info = Deimos::PollInfo.last
        config.full_table = true
        expect(MyProducer).to receive(:poll_query).at_least(:once).and_call_original
        expect(poller).to receive(:process_and_touch_info).ordered.
          with([old_widget, widgets[0], widgets[1]], anything).and_wrap_original do |m, *args|
            m.call(*args)
            expect(info.reload.last_sent.in_time_zone).to eq(time_value(mins: -61, secs: 32))
            expect(info.last_sent_id).to eq(widgets[1].id)
          end
        expect(poller).to receive(:process_and_touch_info).ordered.
          with([widgets[2], widgets[3], widgets[4]], anything).and_call_original
        expect(poller).to receive(:process_and_touch_info).ordered.
          with([widgets[5], widgets[6]], anything).and_call_original
        poller.process_updates

        # this is the updated_at of widgets[6]
        expect(info.reload.last_sent.in_time_zone).to eq(time_value(mins: -61, secs: 37))
        expect(info.last_sent_id).to eq(widgets[6].id)

        last_widget.update_attribute(:updated_at, time_value(mins: -250))

        travel 61.seconds
        # should reprocess the table
        expect(poller).to receive(:process_and_touch_info).ordered.
          with([last_widget, old_widget, widgets[0]], anything).and_call_original
        expect(poller).to receive(:process_and_touch_info).ordered.
          with([widgets[1], widgets[2], widgets[3]], anything).and_call_original
        expect(poller).to receive(:process_and_touch_info).ordered.
          with([widgets[4], widgets[5], widgets[6]], anything).and_call_original
        poller.process_updates

        expect(info.reload.last_sent.in_time_zone).to eq(time_value(mins: -61, secs: 37))
        expect(info.last_sent_id).to eq(widgets[6].id)
      end

      it 'should send events across multiple batches' do
        allow(Deimos.config.logger).to receive(:info)
        allow(MyProducer).to receive(:poll_query).and_call_original
        expect(poller).to receive(:process_and_touch_info).ordered.
          with([widgets[0], widgets[1], widgets[2]], anything).and_call_original
        expect(poller).to receive(:process_and_touch_info).ordered.
          with([widgets[3], widgets[4], widgets[5]], anything).and_call_original
        expect(poller).to receive(:process_and_touch_info).ordered.
          with([widgets[6]], anything).and_call_original
        poller.process_updates

        expect(MyProducer).to have_received(:poll_query).
          with(time_from: time_value(mins: -61),
               time_to: time_value(secs: -2),
               column_name: :updated_at,
               min_id: 0)

        travel 61.seconds
        # process the last widget which came in during the delay
        expect(poller).to receive(:process_and_touch_info).with([last_widget], anything).
          and_call_original
        poller.process_updates

        # widgets[6] updated_at value
        expect(MyProducer).to have_received(:poll_query).
          with(time_from: time_value(mins: -61, secs: 37),
               time_to: time_value(secs: 59), # plus 61 seconds minus 2 seconds for delay
               column_name: :updated_at,
               min_id: widgets[6].id)

        travel 61.seconds
        # nothing else to process
        expect(poller).not_to receive(:process_and_touch_info)
        poller.process_updates
        poller.process_updates

        expect(MyProducer).to have_received(:poll_query).
          with(time_from: time_value(secs: -1),
               time_to: time_value(secs: 120), # plus 122 seconds minus 2 seconds
               column_name: :updated_at,
               min_id: last_widget.id)
        expect(MyProducer).to have_received(:poll_query).
          with(time_from: time_value(secs: 122),
               time_to: time_value(secs: 120), # yes this is weird but it's because of travel_to
               column_name: :updated_at,
               min_id: last_widget.id)
        expect(Deimos.config.logger).to have_received(:info).
          with('Poll MyProducer: ["my-topic-with-id"] complete at 2015-05-05 00:59:58 -0400 (3 batches, 0 errored batches, 7 processed messages)')
      end

      it 'should update PollInfo timestamp after processing' do
        poll_before = Deimos::PollInfo.last
        poller.process_updates
        poll_after = Deimos::PollInfo.last
        expect(poll_after.last_sent).to be >= poll_before.last_sent
      end

      it 'should update PollInfo timestamp when there are no records to process' do
        allow(poller).to receive(:fetch_results).and_return([])
        poll_before = Deimos::PollInfo.last
        poller.process_updates
        poll_after = Deimos::PollInfo.last
        expect(poll_after.last_sent).to be >= poll_before.last_sent
      end

      describe 'errors' do
        before(:each) do
          poller.config.retries = 0
          allow(Deimos.config.logger).to receive(:info)
        end

        after(:each) do
          poller.config.retries = 1
        end

        it 'should recover correctly with errors and save the right ID' do
          widgets.each do |w|
            w.update_attribute(:updated_at, time_value(mins: -61, secs: 30))
          end
          allow(MyProducer).to receive(:poll_query).and_call_original
          expect(poller).to receive(:process_batch).ordered.
            with([widgets[0], widgets[1], widgets[2]]).and_call_original
          expect(poller).to receive(:process_batch).ordered.
            with([widgets[3], widgets[4], widgets[5]]).and_raise('OH NOES')
          expect(poller).to receive(:process_batch).ordered.
            with([widgets[6]]).and_call_original

          poller.process_updates

          expect(MyProducer).to have_received(:poll_query).
            with(time_from: time_value(mins: -61),
                 time_to: time_value(secs: -2),
                 column_name: :updated_at,
                 min_id: 0)

          info = Deimos::PollInfo.last
          expect(info.last_sent.in_time_zone).to eq(time_value(mins: -61, secs: 30))
          expect(info.last_sent_id).to eq(widgets[6].id)
          expect(Deimos.config.logger).to have_received(:info).
            with('Poll MyProducer: ["my-topic-with-id"] complete at 2015-05-05 00:59:58 -0400 (2 batches, 1 errored batches, 7 processed messages)')
        end
      end
    end
  end

  describe 'multi_producer_pollers' do
    include_context 'with widgets'

    let(:poller) do
      poller = Deimos::Utils::DbPoller.class_for_config(config).new(config)
      allow(poller).to receive(:sleep)
      poller
    end

    let(:config) { Deimos.config.db_poller_objects.first.dup }

    before(:each) do
      Widget.delete_all
      producer_class = Class.new(Deimos::ActiveRecordProducer) do
        record_class Widget

        # :nodoc:
        def self.generate_payload(attrs, widget)
          super.merge(message_id: widget.generated_id)
        end
      end
      stub_const('ProducerOne', producer_class)
      stub_const('ProducerTwo', producer_class)

      Karafka::App.routes.redraw do
        topic 'my-topic-with-id' do
          schema 'MySchemaWithId'
          namespace 'com.my-namespace'
          key_config none: true
          producer_class ProducerOne
        end
        topic 'my-topic-with-id2' do
          schema 'MySchemaWithId'
          namespace 'com.my-namespace'
          key_config none: true
          producer_class ProducerTwo
        end
      end

      poller_class = Class.new(Deimos::Utils::DbPoller::StateBased) do
        def self.producers
          [ProducerOne, ProducerTwo]
        end

        def self.poll_query(*)
          Widget.where(publish_status: nil)
        end
      end
      stub_const('Deimos::Utils::DbPoller::MultiProducerPoller', poller_class)
    end

    it 'should publish to two different kafka topics from two producers' do
      Deimos.configure do
        db_poller do
          poller_class 'Deimos::Utils::DbPoller::MultiProducerPoller'
          mode :state_based
          state_column :publish_status
          publish_timestamp_column :published_at
          published_state 'PUBLISHED'
          failed_state 'PUBLISH_FAILED'
          run_every 1.minute
        end
      end

      widgets = (1..3).map do |i|
        Widget.create!(test_id: 'some_id', some_int: i,
                       updated_at: time_value(mins: -61, secs: 30 + i),
                       publish_status: nil, published_at: nil)
      end
      poller.retrieve_poll_info
      allow(Deimos::Utils::DbPoller::MultiProducerPoller).to receive(:poll_query).and_call_original
      allow(ProducerOne).to receive(:send_events)
      allow(ProducerTwo).to receive(:send_events)
      expect(Deimos::Utils::DbPoller::MultiProducerPoller).to receive(:poll_query).at_least(:once)
      poller.process_updates

      expect(ProducerOne).to have_received(:send_events).twice.with(widgets)
      expect(widgets.map(&:reload).map(&:publish_status)).to eq(%w(PUBLISHED PUBLISHED PUBLISHED))
    end

    it 'should raise an error if producer_class and poller_class are both not configured' do
      Deimos.configure do
        db_poller do
          mode :state_based
          state_column :publish_status
          publish_timestamp_column :published_at
          published_state 'PUBLISHED'
          failed_state 'PUBLISH_FAILED'
          run_every 1.minute
        end
      end
      expect { described_class.new(config) }.to raise_error('No producers have been set for this DB poller!')
    end
  end
end
# rubocop:enable Layout/LineLength
