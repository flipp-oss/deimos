RSpec.describe Schemas::MyNamespace::MySchema do
  let(:key) { Schemas::MyNamespace::MySchemaKey.new(test_id: 123) }

  it 'should produce a tombstone with a hash' do
    result = described_class.tombstone({test_id: 123})
    expect(result.payload_key).to eq(key)
    expect(result.to_h).to eq({ payload_key: { 'test_id' => 123}})
  end

  it 'should work with a record' do
    key = Schemas::MyNamespace::MySchemaKey.new(test_id: 123)
    result = described_class.tombstone(key)
    expect(result.payload_key).to eq(key)
    expect(result.to_h).to eq({ payload_key: { 'test_id' => 123}})
  end
end
