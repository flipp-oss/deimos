# frozen_string_literal: true

RSpec.describe Deimos::ActiveRecordConsume::BatchSlicer do
  describe '#slice' do
    let(:batch) do
      [
        Deimos::Message.new({ v: 1 }, key: 'C'),
        Deimos::Message.new({ v: 123 }, key: 'A'),
        Deimos::Message.new({ v: 999 }, key: 'B'),
        Deimos::Message.new({ v: 456 }, key: 'A'),
        Deimos::Message.new({ v: 2 }, key: 'C'),
        Deimos::Message.new({ v: 3 }, key: 'C')
      ]
    end

    it 'should slice a batch by key' do
      slices = described_class.slice(batch)

      expect(slices).
        to match([
                   contain_exactly(Deimos::Message.new({ v: 1 }, key: 'C'), Deimos::Message.new({ v: 123 }, key: 'A'),
                                   Deimos::Message.new({ v: 999 }, key: 'B')),
                   contain_exactly(Deimos::Message.new({ v: 456 }, key: 'A'), Deimos::Message.new({ v: 2 }, key: 'C')),
                   contain_exactly(Deimos::Message.new({ v: 3 }, key: 'C'))
                 ])
    end

    it 'should handle empty batches' do
      slices = described_class.slice([])

      expect(slices).to be_empty
    end
  end
end
