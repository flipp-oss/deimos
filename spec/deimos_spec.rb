# frozen_string_literal: true

describe Deimos do

  it 'should have a version number' do
    expect(Deimos::VERSION).not_to be_nil
  end

  describe '#start_outbox_backend!' do
    it 'should start if backend is outbox and thread_count is > 0' do
      signal_handler = instance_double(Sigurd::SignalHandler)
      allow(signal_handler).to receive(:run!)
      expect(Sigurd::Executor).to receive(:new).
        with(anything, sleep_seconds: 5, logger: anything).and_call_original
      expect(Sigurd::SignalHandler).to receive(:new) do |executor|
        expect(executor.runners.size).to eq(2)
        signal_handler
      end
      described_class.configure do |config|
        config.producers.backend = :outbox
      end
      described_class.start_outbox_backend!(thread_count: 2)
    end

    it 'should not start if backend is not db' do
      expect(Sigurd::SignalHandler).not_to receive(:new)
      described_class.configure do |config|
        config.producers.backend = :kafka
      end
      expect { described_class.start_outbox_backend!(thread_count: 2) }.
        to raise_error('Publish backend is not set to :outbox, exiting')
    end

    it 'should not start if thread_count is nil' do
      expect(Sigurd::SignalHandler).not_to receive(:new)
      described_class.configure do |config|
        config.producers.backend = :outbox
      end
      expect { described_class.start_outbox_backend!(thread_count: nil) }.
        to raise_error('Thread count is not given or set to zero, exiting')
    end

    it 'should not start if thread_count is 0' do
      expect(Sigurd::SignalHandler).not_to receive(:new)
      described_class.configure do |config|
        config.producers.backend = :outbox
      end
      expect { described_class.start_outbox_backend!(thread_count: 0) }.
        to raise_error('Thread count is not given or set to zero, exiting')
    end
  end

  specify '#producer_for' do
    allow(described_class).to receive(:producer_for).and_call_original
    Karafka::App.routes.redraw do
      topic 'main-broker' do
        active false
        kafka({
                'bootstrap.servers': 'broker1:9092'
              })
      end
      topic 'main-broker2' do
        active false
        kafka({
                'bootstrap.servers': 'broker1:9092'
              })
      end
      topic 'other-broker' do
        active false
        kafka({
                'bootstrap.servers': 'broker2:9092'
              })
      end
    end
    described_class.setup_producers

    producer1 = described_class.producer_for('main-broker')
    producer2 = described_class.producer_for('main-broker2')
    producer3 = described_class.producer_for('other-broker')
    expect(producer1).to eq(producer2)
    expect(producer1.config.kafka[:'bootstrap.servers']).to eq('broker1:9092')
    expect(producer3.config.kafka[:'bootstrap.servers']).to eq('broker2:9092')
  end

end
