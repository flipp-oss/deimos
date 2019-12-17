# frozen_string_literal: true

describe Deimos do

  let(:phobos_configuration) do
    { 'logger' =>
        { 'file' => 'log/phobos.log',
          'stdout_json' => false,
          'level' => 'debug',
          'ruby_kafka' =>
              { 'level' => 'debug' } },
      'kafka' =>
        { 'client_id' => 'phobos',
          'connect_timeout' => 15,
          'socket_timeout' => 15,
          'seed_brokers' => 'my_seed_broker.com',
          'ssl_ca_cert' => 'my_ssl_ca_cert',
          'ssl_client_cert' => 'my_ssl_client_cert',
          'ssl_client_cert_key' => 'my_ssl_client_cert_key' },
      'producer' =>
        { 'ack_timeout' => 5,
          'required_acks' => :all,
          'max_retries' => 2,
          'retry_backoff' => 1,
          'max_buffer_size' => 10_000,
          'max_buffer_bytesize' => 10_000_000,
          'compression_codec' => nil,
          'compression_threshold' => 1,
          'max_queue_size' => 10_000,
          'delivery_threshold' => 0,
          'delivery_interval' => 0 },
      'consumer' =>
        { 'session_timeout' => 300,
          'offset_commit_interval' => 10,
          'offset_commit_threshold' => 0,
          'heartbeat_interval' => 10 },
      'backoff' =>
        { 'min_ms' => 1000,
          'max_ms' => 60_000 },
      'listeners' => [
        { 'handler' => 'ConsumerTest::MyConsumer',
          'topic' => 'my_consume_topic',
          'group_id' => 'my_group_id',
          'max_bytes_per_partition' => 524_288 },
        { 'handler' => 'ConsumerTest::MyBatchConsumer',
          'topic' => 'my_batch_consume_topic',
          'group_id' => 'my_batch_group_id',
          'delivery' => 'inline_batch' }
      ],
      'custom_logger' => nil,
      'custom_kafka_logger' => nil }
  end

  let(:config_path) { File.join(File.dirname(__FILE__), 'phobos.yml') }

  it 'should have a version number' do
    expect(Deimos::VERSION).not_to be_nil
  end

  it 'should error if required_acks is not all' do
    expect {
      described_class.configure do |config|
        config.producers.backend = :db
        config.phobos_config_file = File.join(File.dirname(__FILE__), 'phobos.bad_db.yml')
      end
    }.to raise_error('Cannot set producers.backend to :db unless producers.required_acks is set to ":all"!')
  end

  describe '#start_db_backend!' do
    before(:each) do
      allow(described_class).to receive(:run_db_backend)
    end

    it 'should start if backend is db and thread_count is > 0' do
      signal_handler = instance_double(Deimos::Utils::SignalHandler)
      allow(signal_handler).to receive(:run!)
      expect(Deimos::Utils::Executor).to receive(:new).
        with(anything, sleep_seconds: 5, logger: anything).and_call_original
      expect(Deimos::Utils::SignalHandler).to receive(:new) do |executor|
        expect(executor.runners.size).to eq(2)
        signal_handler
      end
      described_class.configure do |config|
        config.producers.backend = :db
      end
      described_class.start_db_backend!(thread_count: 2)
    end

    it 'should not start if backend is not db' do
      expect(Deimos::Utils::SignalHandler).not_to receive(:new)
      described_class.configure do |config|
        config.producers.backend = :kafka
      end
      expect { described_class.start_db_backend!(thread_count: 2) }.
        to raise_error('Publish backend is not set to :db, exiting')
    end

    it 'should not start if thread_count is nil' do
      expect(Deimos::Utils::SignalHandler).not_to receive(:new)
      described_class.configure do |config|
        config.producers.backend = :db
      end
      expect { described_class.start_db_backend!(thread_count: nil) }.
        to raise_error('Thread count is not given or set to zero, exiting')
    end

    it 'should not start if thread_count is 0' do
      expect(Deimos::Utils::SignalHandler).not_to receive(:new)
      described_class.configure do |config|
        config.producers.backend = :db
      end
      expect { described_class.start_db_backend!(thread_count: 0) }.
        to raise_error('Thread count is not given or set to zero, exiting')
    end

    describe 'delivery configuration' do
      before(:each) do
        allow(YAML).to receive(:load).and_return(phobos_configuration)
      end

      it 'should not raise an error with properly configured handlers' do
        path = config_path # for scope issues in the block below
        # Add explicit consumers
        phobos_configuration['listeners'] << { 'handler' => 'ConsumerTest::MyConsumer',
                                               'delivery' => 'message' }
        phobos_configuration['listeners'] << { 'handler' => 'ConsumerTest::MyConsumer',
                                               'delivery' => 'batch' }

        expect {
          described_class.configure { |c| c.phobos_config_file = path }
        }.not_to raise_error
      end

      it 'should raise an error if BatchConsumers do not have inline_batch delivery' do
        path = config_path # for scope issues in the block below
        phobos_configuration['listeners'] = [{ 'handler' => 'ConsumerTest::MyBatchConsumer',
                                               'delivery' => 'message' }]

        expect {
          described_class.configure { |c| c.phobos_config_file = path }
        }.to raise_error('BatchConsumer ConsumerTest::MyBatchConsumer must have delivery set to `inline_batch`')
      end

      it 'should raise an error if Consumers do not have message or batch delivery' do
        path = config_path # for scope issues in the block below
        phobos_configuration['listeners'] = [{ 'handler' => 'ConsumerTest::MyConsumer',
                                               'delivery' => 'inline_batch' }]

        expect {
          described_class.configure { |c| c.phobos_config_file = path }
        }.to raise_error('Non-batch Consumer ConsumerTest::MyConsumer must have delivery set to `message` or `batch`')
      end

      it 'should treat nil as `batch`' do
        path = config_path # for scope issues in the block below
        phobos_configuration['listeners'] = [{ 'handler' => 'ConsumerTest::MyConsumer' }]

        expect {
          described_class.configure { |c| c.phobos_config_file = path }
        }.not_to raise_error
      end

    end
  end
end
