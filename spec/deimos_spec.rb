# frozen_string_literal: true

describe Deimos do

  it 'should have a version number' do
    expect(Deimos::VERSION).not_to be_nil
  end

  describe '#start_db_backend!' do
    it 'should start if backend is db and thread_count is > 0' do
      signal_handler = instance_double(Sigurd::SignalHandler)
      allow(signal_handler).to receive(:run!)
      expect(Sigurd::Executor).to receive(:new).
        with(anything, sleep_seconds: 5, logger: anything).and_call_original
      expect(Sigurd::SignalHandler).to receive(:new) do |executor|
        expect(executor.runners.size).to eq(2)
        signal_handler
      end
      described_class.configure do |config|
        config.producers.backend = :db
      end
      described_class.start_db_backend!(thread_count: 2)
    end

    it 'should not start if backend is not db' do
      expect(Sigurd::SignalHandler).not_to receive(:new)
      described_class.configure do |config|
        config.producers.backend = :kafka
      end
      expect { described_class.start_db_backend!(thread_count: 2) }.
        to raise_error('Publish backend is not set to :db, exiting')
    end

    it 'should not start if thread_count is nil' do
      expect(Sigurd::SignalHandler).not_to receive(:new)
      described_class.configure do |config|
        config.producers.backend = :db
      end
      expect { described_class.start_db_backend!(thread_count: nil) }.
        to raise_error('Thread count is not given or set to zero, exiting')
    end

    it 'should not start if thread_count is 0' do
      expect(Sigurd::SignalHandler).not_to receive(:new)
      described_class.configure do |config|
        config.producers.backend = :db
      end
      expect { described_class.start_db_backend!(thread_count: 0) }.
        to raise_error('Thread count is not given or set to zero, exiting')
    end
  end

end
