# frozen_string_literal: true

RSpec.describe Deimos::Utils::SignalHandler do
  describe '#run!' do

    it 'starts and stops the runner' do
      runner = TestRunners::TestRunner.new
      expect(runner).to receive(:start)
      expect(runner).to receive(:stop)

      signal_handler = described_class.new(runner)
      signal_handler.send(:unblock, described_class::SIGNALS.first)
      signal_handler.run!
    end
  end
end
