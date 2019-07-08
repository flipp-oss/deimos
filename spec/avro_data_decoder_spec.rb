# frozen_string_literal: true

describe Deimos::AvroDataDecoder do

  let(:decoder) do
    decoder = described_class.new(schema: 'MySchema',
                                  namespace: 'com.my-namespace')
    allow(decoder).to(receive(:decode)) { |payload| payload }
    decoder
  end

  it 'should decode a key' do
    # reset stub from TestHelpers
    allow(described_class).to receive(:new).and_call_original
    expect(decoder.decode_key({ 'test_id' => '123' }, 'test_id')).to eq('123')
  end

end
