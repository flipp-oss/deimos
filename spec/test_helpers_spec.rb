# frozen_string_literal: true

require 'deimos/test_helpers'

RSpec.describe Deimos::TestHelpers do

  describe '.with_mock_backends' do
    before(:each) do
      Karafka::App.routes.redraw do
        topic 'mock-backend-test' do
          active false
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config field: 'test_id'
        end
      end
    end

    after(:each) do
      Deimos.mock_backends = false
    end

    it 'should set mock_backends to true during the block' do
      expect(Deimos.mock_backends).to be_falsey

      described_class.with_mock_backends do
        expect(Deimos.mock_backends).to be(true)
      end

      expect(Deimos.mock_backends).to be(false)
    end

    it 'should reset mock_backends after the block completes' do
      described_class.with_mock_backends do
        # noop
      end
      expect(Deimos.mock_backends).to be(false)
    end

    it 'should reset mock_backends even if an error occurs in the block' do
      expect {
        described_class.with_mock_backends do
          raise 'Test error'
        end
      }.to raise_error('Test error')
      expect(Deimos.mock_backends).to be(false)
    end

    it 'should reset backends on deserializers' do
      config = Deimos.karafka_config_for(topic: 'mock-backend-test')
      payload_transcoder = config.deserializers[:payload]
      key_transcoder = config.deserializers[:key]

      expect(payload_transcoder).to receive(:reset_backend)
      expect(key_transcoder).to receive(:reset_backend) if key_transcoder.respond_to?(:reset_backend)

      described_class.with_mock_backends do
        # noop
      end
    end

    it 'should use mock backends for schema_backend_class' do
      described_class.with_mock_backends do
        # avro_schema_registry should return avro_validation when mocked
        klass = Deimos.schema_backend_class(backend: :avro_schema_registry)
        expect(klass).to eq(Deimos::SchemaBackends::AvroValidation)
      end

      # Outside the block, should return the real class
      klass = Deimos.schema_backend_class(backend: :avro_schema_registry)
      expect(klass).to eq(Deimos::SchemaBackends::AvroSchemaRegistry)
    end
  end

end
