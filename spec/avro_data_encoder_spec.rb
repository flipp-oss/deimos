# frozen_string_literal: true

require 'avro_turf/messaging'

describe Deimos::AvroDataEncoder do

  let(:encoder) do
    encoder = described_class.new(schema: 'MySchema',
                                  namespace: 'com.my-namespace')
    allow(encoder).to(receive(:encode)) { |payload| payload }
    encoder
  end

  specify 'generate_key_schema' do
    expect_any_instance_of(AvroTurf::SchemaStore).
      to receive(:add_schema).with(
        'type' => 'record',
        'name' => 'MySchema_key',
        'namespace' => 'com.my-namespace',
        'doc' => 'Key for com.my-namespace.MySchema',
        'fields' => [
          {
            'name' => 'test_id',
            'type' => 'string'
          }
        ]
      )
    encoder.send(:_generate_key_schema, 'test_id')
  end

  it 'should encode a key' do
    # reset stub from TestHelpers
    allow(described_class).to receive(:new).and_call_original
    expect(encoder.encode_key('test_id', '123')).to eq('test_id' => '123')
  end

end
