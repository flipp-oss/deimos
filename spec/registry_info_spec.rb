# frozen_string_literal: true

RSpec.describe Deimos::RegistryInfo do
  describe '#initialize' do
    it 'should initialize with url, user, and password' do
      registry_info = described_class.new('http://localhost:8081', 'user1', 'pass1')
      expect(registry_info.url).to eq('http://localhost:8081')
      expect(registry_info.user).to eq('user1')
      expect(registry_info.password).to eq('pass1')
    end

    it 'should allow nil user and password' do
      registry_info = described_class.new('http://localhost:8081', nil, nil)
      expect(registry_info.url).to eq('http://localhost:8081')
      expect(registry_info.user).to be_nil
      expect(registry_info.password).to be_nil
    end

    it 'should allow setting attributes' do
      registry_info = described_class.new('http://localhost:8081', 'user1', 'pass1')
      registry_info.url = 'http://newhost:8081'
      registry_info.user = 'user2'
      registry_info.password = 'pass2'

      expect(registry_info.url).to eq('http://newhost:8081')
      expect(registry_info.user).to eq('user2')
      expect(registry_info.password).to eq('pass2')
    end
  end
end
