# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Deimos::Utils::Executor do

  let(:executor) { described_class.new(runners) }
  let(:runners) { (1..2).map { |i| TestRunners::TestRunner.new(i) } }

  it 'starts and stops configured runners' do
    runners.each do |r|
      expect(r.started).to be_falsey
      expect(r.stopped).to be_falsey
    end
    executor.start
    wait_for do
      runners.each do |r|
        expect(r.started).to be_truthy
        expect(r.stopped).to be_falsey
      end
      executor.stop
      runners.each do |r|
        expect(r.started).to be_truthy
        expect(r.stopped).to be_truthy
      end
    end
  end

  it 'reconnects crashed runners' do
    allow(executor).to receive(:handle_crashed_runner).and_call_original
    runners.each { |r| r.should_error = true }
    executor.start
    wait_for do
      expect(executor).to have_received(:handle_crashed_runner).with(runners[0], anything, 0).once
      expect(executor).to have_received(:handle_crashed_runner).with(runners[1], anything, 0).once
      runners.each { |r| expect(r.started).to be_truthy }
      executor.stop
    end
  end

end
