# frozen_string_literal: true

RSpec.describe Deimos::Utils::DeadlockRetry do
  include_context 'with widgets'

  before(:each) do
    allow(described_class).to receive(:sleep)
  end

  describe 'deadlock handling' do
    let(:batch) { [{ key: 1, payload: { test_id: 'abc', some_int: 3 } }] }

    it 'should retry deadlocks 3 times' do
      # Should receive original attempt + 2 retries
      expect(Widget).
        to receive(:create).
        and_raise(ActiveRecord::Deadlocked.new('Lock wait timeout exceeded')).
        exactly(3).times

      # After 3 tries, should let it bubble up
      expect {
        described_class.wrap do
          Widget.create(test_id: 'abc')
        end
      }.to raise_error(ActiveRecord::Deadlocked)
    end

    it 'should stop retrying deadlocks after success' do
      allow(Widget).
        to receive(:create).
        with(hash_including(test_id: 'first')).
        and_call_original

      # Fail on first attempt, succeed on second
      expect(Widget).
        to receive(:create).
        with(hash_including(test_id: 'second')).
        and_raise(ActiveRecord::Deadlocked.new('Deadlock found when trying to get lock')).
        once.
        ordered

      expect(Widget).
        to receive(:create).
        with(hash_including(test_id: 'second')).
        once.
        ordered.
        and_call_original

      # Should not raise anything
      described_class.wrap do
        Widget.create(test_id: 'first')
        Widget.create(test_id: 'second')
      end

      expect(Widget.all).to contain_exactly(have_attributes(test_id: 'first'), have_attributes(test_id: 'second'))
    end

    it 'should not retry non-deadlock exceptions' do
      expect(Widget).
        to receive(:create).
        and_raise(ActiveRecord::StatementInvalid.new('Oops!!')).
        once

      expect {
        described_class.wrap do
          Widget.create(test_id: 'abc')
        end
      }.to raise_error(ActiveRecord::StatementInvalid, 'Oops!!')
    end
  end
end
