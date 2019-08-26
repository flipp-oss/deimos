# frozen_string_literal: true

describe Deimos do

  it 'should have a version number' do
    expect(Deimos::VERSION).not_to be_nil
  end

  specify 'configure' do
    phobos_configuration = { 'logger' =>
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
                                 'max_bytes_per_partition' => 524_288 }
                             ],
                             'custom_logger' => nil,
                             'custom_kafka_logger' => nil }

    expect(Phobos).to receive(:configure).with(phobos_configuration)
    allow(described_class).to receive(:ssl_var_contents) { |key| key }
    described_class.configure do |config|
      config.phobos_config_file = File.join(File.dirname(__FILE__), 'phobos.yml')
      config.seed_broker = 'my_seed_broker.com'
      config.ssl_enabled = true
      config.ssl_ca_cert = 'my_ssl_ca_cert'
      config.ssl_client_cert = 'my_ssl_client_cert'
      config.ssl_client_cert_key = 'my_ssl_client_cert_key'
    end
  end

  it 'should error if required_acks is not all' do
    expect {
      described_class.configure do |config|
        config.publish_backend = :db
        config.phobos_config_file = File.join(File.dirname(__FILE__), 'phobos.bad_db.yml')
      end
    }.to raise_error('Cannot set publish_backend to :db unless required_acks is set to ":all" in phobos.yml!')
  end

  describe '#start_db_backend!' do
    before(:each) do
      allow(described_class).to receive(:run_db_backend)
    end

    it 'should start if backend is db and num_producer_threads is > 0' do
      signal_handler = instance_double(Deimos::Utils::SignalHandler)
      allow(signal_handler).to receive(:run!)
      expect(Deimos::Utils::Executor).to receive(:new).
        with(anything, sleep_seconds: 5, logger: anything).and_call_original
      expect(Deimos::Utils::SignalHandler).to receive(:new) do |executor|
        expect(executor.runners.size).to eq(2)
        signal_handler
      end
      described_class.configure do |config|
        config.publish_backend = :db
      end
      described_class.start_db_backend!(thread_count: 2)
    end

    it 'should not start if backend is not db' do
      expect(Deimos::Utils::SignalHandler).not_to receive(:new)
      described_class.configure do |config|
        config.publish_backend = :kafka
      end
      expect { described_class.start_db_backend!(thread_count: 2) }.
        to raise_error('Publish backend is not set to :db, exiting')
    end

    it 'should not start if num_producer_threads is nil' do
      expect(Deimos::Utils::SignalHandler).not_to receive(:new)
      described_class.configure do |config|
        config.publish_backend = :db
      end
      expect { described_class.start_db_backend!(thread_count: nil) }.
        to raise_error('Thread count is not given or set to zero, exiting')
    end

    it 'should not start if num_producer_threads is 0' do
      expect(Deimos::Utils::SignalHandler).not_to receive(:new)
      described_class.configure do |config|
        config.publish_backend = :db
      end
      expect { described_class.start_db_backend!(thread_count: 0) }.
        to raise_error('Thread count is not given or set to zero, exiting')
    end

  end
end
