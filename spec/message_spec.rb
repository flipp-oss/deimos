# frozen_string_literal: true

RSpec.describe(Deimos::Message) do
  it 'should detect tombstones' do
    expect(described_class.new(nil, nil, key: 'key1')).
      to be_tombstone
    expect(described_class.new({ v: 'val1' }, nil, key: 'key1')).
      not_to be_tombstone
    expect(described_class.new({ v: '' }, nil, key: 'key1')).
      not_to be_tombstone
    expect(described_class.new({ v: 'val1' }, nil, key: nil)).
      not_to be_tombstone
  end

  it 'can support complex keys/values' do
    expect { described_class.new({ a: 1, b: 2 }, nil, key: { c: 3, d: 4 }) }.
      not_to raise_exception
  end
end
