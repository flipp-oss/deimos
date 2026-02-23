# frozen_string_literal: true

describe Deimos do

  it 'should have a version number' do
    expect(Deimos::VERSION).not_to be_nil
  end

  describe '#start_outbox_backend!' do
    it 'should start if backend is outbox and thread_count is > 0' do
      signal_handler = instance_double(Sigurd::SignalHandler)
      allow(signal_handler).to receive(:run!)
      expect(Sigurd::Executor).to receive(:new).
        with(anything, sleep_seconds: 5, logger: anything).and_call_original
      expect(Sigurd::SignalHandler).to receive(:new) do |executor|
        expect(executor.runners.size).to eq(2)
        signal_handler
      end
      described_class.configure do |config|
        config.producers.backend = :outbox
      end
      described_class.start_outbox_backend!(thread_count: 2)
    end

    it 'should not start if backend is not db' do
      expect(Sigurd::SignalHandler).not_to receive(:new)
      described_class.configure do |config|
        config.producers.backend = :kafka
      end
      expect { described_class.start_outbox_backend!(thread_count: 2) }.
        to raise_error('Publish backend is not set to :outbox, exiting')
    end

    it 'should not start if thread_count is nil' do
      expect(Sigurd::SignalHandler).not_to receive(:new)
      described_class.configure do |config|
        config.producers.backend = :outbox
      end
      expect { described_class.start_outbox_backend!(thread_count: nil) }.
        to raise_error('Thread count is not given or set to zero, exiting')
    end

    it 'should not start if thread_count is 0' do
      expect(Sigurd::SignalHandler).not_to receive(:new)
      described_class.configure do |config|
        config.producers.backend = :outbox
      end
      expect { described_class.start_outbox_backend!(thread_count: 0) }.
        to raise_error('Thread count is not given or set to zero, exiting')
    end
  end

  specify '#producer_for' do
    allow(described_class).to receive(:producer_for).and_call_original
    Karafka::App.routes.redraw do
      topic 'main-broker' do
        active false
        kafka({
                'bootstrap.servers': 'broker1:9092'
              })
      end
      topic 'main-broker2' do
        active false
        kafka({
                'bootstrap.servers': 'broker1:9092'
              })
      end
      topic 'other-broker' do
        active false
        kafka({
                'bootstrap.servers': 'broker2:9092'
              })
      end
    end
    described_class.setup_producers

    producer1 = described_class.producer_for('main-broker')
    producer2 = described_class.producer_for('main-broker2')
    producer3 = described_class.producer_for('other-broker')
    expect(producer1).to eq(producer2)
    expect(producer1.config.kafka[:'bootstrap.servers']).to eq('broker1:9092')
    expect(producer3.config.kafka[:'bootstrap.servers']).to eq('broker2:9092')
  end

  describe '#schema_backend_for' do
    it 'should return a schema backend for a given topic' do
      Karafka::App.routes.redraw do
        topic 'backend-test-topic' do
          active false
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config none: true
        end
      end

      backend = described_class.schema_backend_for('backend-test-topic')
      expect(backend.inspect).to eq('Type AvroValidation Schema: com.my-namespace.MySchema Key schema: ')
    end

    it 'should use topic-specific schema_backend if configured' do
      Karafka::App.routes.redraw do
        topic 'backend-test-topic-local' do
          active false
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config none: true
          schema_backend :avro_local
        end
      end

      backend = described_class.schema_backend_for('backend-test-topic-local')
      expect(backend).to be_a(Deimos::SchemaBackends::AvroLocal)
    end

    it 'should fall back to global schema backend config' do
      described_class.config.schema.backend = :avro_validation
      Karafka::App.routes.redraw do
        topic 'backend-test-topic-global' do
          active false
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config none: true
        end
      end

      backend = described_class.schema_backend_for('backend-test-topic-global')
      expect(backend).to be_a(Deimos::SchemaBackends::AvroValidation)
    end

    it 'should use topic-specific registry configuration' do
      Karafka::App.routes.redraw do
        topic 'backend-test-topic-registry' do
          active false
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config none: true
          registry_url 'http://topic-specific-registry:8081'
          registry_user 'topic-user'
          registry_password 'topic-password'
        end
      end

      backend = described_class.schema_backend_for('backend-test-topic-registry')
      # Backend will be AvroValidation in test mode, but should have registry_info
      expect(backend.registry_info).not_to be_nil
      expect(backend.registry_info.url).to eq('http://topic-specific-registry:8081')
      expect(backend.registry_info.user).to eq('topic-user')
      expect(backend.registry_info.password).to eq('topic-password')
    end

    it 'should create backend with nil registry_info when not specified' do
      Karafka::App.routes.redraw do
        topic 'backend-test-topic-no-registry' do
          active false
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config none: true
        end
      end

      backend = described_class.schema_backend_for('backend-test-topic-no-registry')
      # registry_info should be nil when not specified in topic config
      expect(backend.registry_info).to be_nil
    end
  end

  describe 'configure' do
    it 'should reset cached backends when configure is called again' do
      Karafka::App.routes.redraw do
        topic 'configure-test-topic' do
          active false
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config none: true
        end
      end

      topic_config = described_class.karafka_configs.find { |c| c.name == 'configure-test-topic' }
      payload_transcoder = topic_config.deserializers[:payload]

      # Access the backend to cache it
      first_backend = payload_transcoder.backend

      # Call configure again (simulating a second configure call after topics are defined)
      described_class.configure do |config|
        config.schema.backend = :avro_validation
      end

      # The cached backend should have been reset, so a new one is created
      second_backend = payload_transcoder.backend
      expect(second_backend).not_to equal(first_backend)
    end
  end

  describe '#schema_backend_class with mock_backends' do
    after(:each) do
      described_class.mock_backends = false
    end

    it 'should return the mock backend when mock_backends is true' do
      described_class.mock_backends = true
      klass = described_class.schema_backend_class(backend: :avro_schema_registry)
      expect(klass).to eq(Deimos::SchemaBackends::AvroValidation)
    end

    it 'should return the real backend when mock_backends is false' do
      described_class.mock_backends = false
      klass = described_class.schema_backend_class(backend: :avro_schema_registry)
      expect(klass).to eq(Deimos::SchemaBackends::AvroSchemaRegistry)
    end

    it 'should use proto_local for proto_schema_registry when mocked' do
      described_class.mock_backends = true
      klass = described_class.schema_backend_class(backend: :proto_schema_registry)
      expect(klass).to eq(Deimos::SchemaBackends::ProtoLocal)
    end
  end

end
