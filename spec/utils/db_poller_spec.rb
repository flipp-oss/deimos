# frozen_string_literal: true

# @param seconds [Integer]
# @return [Time]
def time_value(secs: 0, mins: 0)
  Time.local(2015, 5, 5, 1, 0, 0) + (secs + (mins * 60))
end

each_db_config(Deimos::Utils::DbPoller) do

  before(:each) do
    Deimos::PollInfo.delete_all
  end

  describe '#start!' do

    before(:each) do
      producer_class = Class.new(Deimos::Producer) do
        schema 'MySchema'
        namespace 'com.my-namespace'
        topic 'my-topic'
        key_config field: 'test_id'
      end
      stub_const('MyProducer', producer_class)

      producer_class = Class.new(Deimos::Producer) do
        schema 'MySchemaWithId'
        namespace 'com.my-namespace'
        topic 'my-topic'
        key_config plain: true
      end
      stub_const('MyProducerWithID', producer_class)
    end

    it 'should raise an error if no pollers configured' do
      Deimos.configure {}
      expect { described_class.start! }.to raise_error('No pollers configured!')
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

      allow(Deimos::Utils::DbPoller).to receive(:new)
      signal_double = instance_double(Deimos::Utils::SignalHandler, run!: nil)
      allow(Deimos::Utils::SignalHandler).to receive(:new).and_return(signal_double)
      described_class.start!
      expect(Deimos::Utils::DbPoller).to have_received(:new).twice
      expect(Deimos::Utils::DbPoller).to have_received(:new).
        with(Deimos.config.db_poller_objects[0])
      expect(Deimos::Utils::DbPoller).to have_received(:new).
        with(Deimos.config.db_poller_objects[1])
    end
  end

  describe 'pollers' do
    include_context 'with widgets'

    let(:poller) do
      poller = described_class.new(config)
      allow(poller).to receive(:sleep)
      poller
    end

    let(:config) { Deimos.config.db_poller_objects.first.dup }

    before(:each) do
      Widget.delete_all
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
      stub_const('MyProducer', producer_class)

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

    specify '#process_batch' do
      travel_to time_value
      widgets = (1..3).map { Widget.create!(test_id: 'some_id', some_int: 4) }
      widgets.last.update_attribute(:updated_at, time_value(mins: -30))
      expect(MyProducer).to receive(:send_events).with(widgets)
      poller.retrieve_poll_info
      poller.process_batch(widgets)
      info = Deimos::PollInfo.last
      expect(info.last_sent.in_time_zone).to eq(time_value(mins: -30))
      expect(info.last_sent_id).to eq(widgets.last.id)
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
        expect(poller).to receive(:process_batch).ordered.
          with([old_widget, widgets[0], widgets[1]]).and_wrap_original do |m, *args|
            m.call(*args)
            expect(info.reload.last_sent.in_time_zone).to eq(time_value(mins: -61, secs: 32))
            expect(info.last_sent_id).to eq(widgets[1].id)
          end
        expect(poller).to receive(:process_batch).ordered.
          with([widgets[2], widgets[3], widgets[4]]).and_call_original
        expect(poller).to receive(:process_batch).ordered.
          with([widgets[5], widgets[6]]).and_call_original
        poller.process_updates

        # this is the updated_at of widgets[6]
        expect(info.reload.last_sent.in_time_zone).to eq(time_value(mins: -61, secs: 37))
        expect(info.last_sent_id).to eq(widgets[6].id)

        last_widget.update_attribute(:updated_at, time_value(mins: -250))

        travel 61.seconds
        # should reprocess the table
        expect(poller).to receive(:process_batch).ordered.
          with([last_widget, old_widget, widgets[0]]).and_call_original
        expect(poller).to receive(:process_batch).ordered.
          with([widgets[1], widgets[2], widgets[3]]).and_call_original
        expect(poller).to receive(:process_batch).ordered.
          with([widgets[4], widgets[5], widgets[6]]).and_call_original
        poller.process_updates

        expect(info.reload.last_sent.in_time_zone).to eq(time_value(mins: -61, secs: 37))
        expect(info.last_sent_id).to eq(widgets[6].id)
      end

      it 'should send events across multiple batches' do
        allow(MyProducer).to receive(:poll_query).and_call_original
        expect(poller).to receive(:process_batch).ordered.
          with([widgets[0], widgets[1], widgets[2]]).and_call_original
        expect(poller).to receive(:process_batch).ordered.
          with([widgets[3], widgets[4], widgets[5]]).and_call_original
        expect(poller).to receive(:process_batch).ordered.
          with([widgets[6]]).and_call_original
        poller.process_updates

        expect(MyProducer).to have_received(:poll_query).
          with(time_from: time_value(mins: -61),
               time_to: time_value(secs: -2),
               column_name: :updated_at,
               min_id: 0)

        travel 61.seconds
        # process the last widget which came in during the delay
        expect(poller).to receive(:process_batch).with([last_widget]).
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
        expect(poller).not_to receive(:process_batch)
        poller.process_updates
        poller.process_updates

        expect(MyProducer).to have_received(:poll_query).twice.
          with(time_from: time_value(secs: -1),
               time_to: time_value(secs: 120), # plus 122 seconds minus 2 seconds
               column_name: :updated_at,
               min_id: last_widget.id)
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

        expect { poller.process_updates }.to raise_exception('OH NOES')

        expect(MyProducer).to have_received(:poll_query).
          with(time_from: time_value(mins: -61),
               time_to: time_value(secs: -2),
               column_name: :updated_at,
               min_id: 0)

        info = Deimos::PollInfo.last
        expect(info.last_sent.in_time_zone).to eq(time_value(mins: -61, secs: 30))
        expect(info.last_sent_id).to eq(widgets[2].id)

        travel 61.seconds
        # process the last widget which came in during the delay
        expect(poller).to receive(:process_batch).ordered.
          with([widgets[3], widgets[4], widgets[5]]).and_call_original
        expect(poller).to receive(:process_batch).with([widgets[6], last_widget]).
          and_call_original
        poller.process_updates
        expect(MyProducer).to have_received(:poll_query).
          with(time_from: time_value(mins: -61, secs: 30),
               time_to: time_value(secs: 59),
               column_name: :updated_at,
               min_id: widgets[2].id)

        expect(info.reload.last_sent.in_time_zone).to eq(time_value(secs: -1))
        expect(info.last_sent_id).to eq(last_widget.id)
      end

    end

  end
end
