# frozen_string_literal: true

each_db_config(Deimos::Utils::DbPoller) do
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

    let(:config) { Deimos.config.db_poller_objects.first }

    before(:each) do
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
      Deimos::PollInfo.delete_all
      Widget.delete_all
      travel_back
    end

    it 'should crash if initialized with an invalid producer' do
      config.producer_class = 'NoProducer'
      expect { described_class.new(config) }.to raise_error('Class NoProducer not found!')
    end

    specify '#retrieve_poll_info' do
      travel_to(Time.zone.local(2020, 0o5, 0o5, 0o5, 0o0, 0o0))
      poller.retrieve_poll_info
      expect(Deimos::PollInfo.count).to eq(1)
      info = Deimos::PollInfo.last
      expect(info.producer).to eq('MyProducer')
      expect(info.last_sent).to eq(Time.new(0))
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
                               last_sent: Time.zone.local(2020, 0o5, 0o5, 0o3, 59, 0o0))
      poller.retrieve_poll_info

      travel_to(Time.zone.local(2020, 0o5, 0o5, 0o5, 0o0, 0o0))
      expect(poller.should_run?).to eq(true)

      # run_every is set to 1 minute

      travel_to(Time.zone.local(2020, 0o5, 0o5, 0o4, 0o1, 0o0))
      expect(poller.should_run?).to eq(true)

      travel_to(Time.zone.local(2020, 0o5, 0o5, 0o3, 59, 30))
      expect(poller.should_run?).to eq(false)

      travel_to(Time.zone.local(2020, 0o5, 0o5, 0o3, 58, 0o0))
      expect(poller.should_run?).to eq(false)
    end

    describe '#process_updates' do
      before(:each) do
        Deimos::PollInfo.create!(producer: 'MyProducer',
                                 last_sent: Time.zone.local(2020, 0o5, 0o4, 22, 59, 0o0))
        travel_to(Time.zone.local(2020, 0o5, 0o5, 0o1, 0o0, 0o0))
        allow(poller).to receive(:process_updates).and_wrap_original do |m|
          m.call
          poller.stop
        end
        allow(MyProducer).to receive(:send_events)
        stub_const('Deimos::Utils::DbPoller::BATCH_SIZE', 3)

        # old widget, earlier than window
        Widget.create!(test_id: 'some_id', some_int: 4,
                       updated_at: Time.local(2020, 0o5, 0o3, 23, 59, 30))
        # new widget, before delay
        Widget.create!(test_id: 'some_id', some_int: 10,
                       updated_at: Time.local(2020, 0o5, 0o5, 0o0, 59, 59))
      end

      let!(:widgets) do
        (1..7).map do |i|
          Widget.create!(test_id: 'some_id', some_int: i,
                         updated_at: Time.local(2020, 0o5, 0o4, 23, 59, 30 + i))
        end
      end

      it 'should update the full table' do
        config.full_table = true
        expect(MyProducer).to receive(:poll_query).
          with(Time.local(2020, 0o5, 0o4, 22, 59, 0o0),
               Time.local(2020, 0o5, 0o5, 0o0, 59, 58),
               :updated_at,
               true).and_call_original
        widgets = Widget.all
        expect(MyProducer).to receive(:send_events).ordered.
          with([widgets[0], widgets[1], widgets[2]])
        expect(MyProducer).to receive(:send_events).ordered.
          with([widgets[3], widgets[4], widgets[5]])
        expect(MyProducer).to receive(:send_events).ordered.
          with([widgets[6], widgets[7], widgets[8]])
        poller.start

        travel 61.seconds
        expect(MyProducer).to receive(:poll_query).
          with(Time.local(2020, 0o5, 0o5, 0o0, 59, 58),
               Time.local(2020, 0o5, 0o5, 0o1, 0o0, 59),
               :updated_at,
               true).and_call_original
        # should reprocess the table
        expect(MyProducer).to receive(:send_events).ordered.
          with([widgets[0], widgets[1], widgets[2]])
        expect(MyProducer).to receive(:send_events).ordered.
          with([widgets[3], widgets[4], widgets[5]])
        expect(MyProducer).to receive(:send_events).ordered.
          with([widgets[6], widgets[7], widgets[8]])
        poller.start

      end

      it 'should send events across multiple batches' do
        expect(MyProducer).to receive(:poll_query).
          with(Time.local(2020, 0o5, 0o4, 22, 59, 0o0),
               Time.local(2020, 0o5, 0o5, 0o0, 59, 58),
               :updated_at,
               false).and_call_original
        expect(MyProducer).to receive(:send_events).ordered.
          with([widgets[0], widgets[1], widgets[2]])
        expect(MyProducer).to receive(:send_events).ordered.
          with([widgets[3], widgets[4], widgets[5]])
        expect(MyProducer).to receive(:send_events).ordered.
          with([widgets[6]])
        poller.start

        travel 61.seconds
        expect(MyProducer).to receive(:poll_query).
          with(Time.local(2020, 0o5, 0o5, 0o0, 59, 58),
               Time.local(2020, 0o5, 0o5, 0o1, 0o0, 59),
               :updated_at,
               false).and_call_original
        # process the last widget which came in during the delay
        expect(MyProducer).to receive(:send_events).with([Widget.find_by_some_int(10)])
        poller.start

        travel 61.seconds
        expect(MyProducer).to receive(:poll_query).
          with(Time.local(2020, 0o5, 0o5, 0o1, 0o0, 59),
               Time.local(2020, 0o5, 0o5, 0o1, 0o2, 0o0),
               :updated_at,
               false).and_call_original
        # nothing else to process
        expect(MyProducer).not_to receive(:send_events)
        poller.start

      end

    end

  end
end
