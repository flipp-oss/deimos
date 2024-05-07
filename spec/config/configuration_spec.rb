# frozen_string_literal: true

# Mock consumer
class MyConfigConsumer < Deimos::Consumer
  # :no-doc:
  def consume
  end
end

# Mock consumer 2
class MyConfigConsumer2 < Deimos::Consumer
  # :no-doc:
  def consume
  end
end

describe Deimos, 'configuration' do
  it 'should configure with deprecated fields' do
    logger = Logger.new(nil)
    described_class.configure do
      kafka_logger logger
      reraise_consumer_errors true
      schema_registry_url 'http://schema.registry'
      schema.use_schema_classes false
      seed_broker 'whatever'
      schema_path 'some_path'
      producer_schema_namespace 'namespace'
      producer_topic_prefix 'prefix'
      disable_producers true
      ssl_enabled true
      ssl_ca_cert 'cert'
      ssl_client_cert 'cert'
      ssl_client_cert_key 'key'
      publish_backend 'db'
      report_lag true
    end

    expect(described_class.config.kafka.logger).to eq(logger)
    expect(described_class.config.consumers.reraise_errors).to eq(true)
    expect(described_class.config.schema.registry_url).to eq('http://schema.registry')
    expect(described_class.config.schema.use_schema_classes).to eq(false)
    expect(described_class.config.kafka.seed_brokers).to eq('whatever')
    expect(described_class.config.producers.schema_namespace).to eq('namespace')
    expect(described_class.config.producers.topic_prefix).to eq('prefix')
    expect(described_class.config.producers.disabled).to eq(true)
    expect(described_class.config.kafka.ssl.enabled).to eq(true)
    expect(described_class.config.kafka.ssl.ca_cert).to eq('cert')
    expect(described_class.config.kafka.ssl.client_cert).to eq('cert')
    expect(described_class.config.kafka.ssl.client_cert_key).to eq('key')
    expect(described_class.config.producers.backend).to eq('db')
    expect(described_class.config.consumers.report_lag).to eq(true)
  end

  it 'reads existing Phobos config YML files' do
    described_class.config.reset!
    described_class.configure { |c| c.phobos_config_file = File.join(File.dirname(__FILE__), '..', 'phobos.yml') }
    expect(described_class.config.phobos_config).to match(
      logger: an_instance_of(Logger),
      backoff: { min_ms: 1000, max_ms: 60_000 },
      consumer: {
        session_timeout: 300,
        offset_commit_interval: 10,
        offset_commit_threshold: 0,
        heartbeat_interval: 10
      },
      custom_kafka_logger: an_instance_of(Logger),
      custom_logger: an_instance_of(Logger),
      kafka: {
        client_id: 'phobos',
        connect_timeout: 15,
        socket_timeout: 15,
        ssl_verify_hostname: true,
        ssl_ca_certs_from_system: false,
        seed_brokers: ['localhost:9092']
      },
      listeners: [
        {
          topic: 'my_consume_topic',
          group_id: 'my_group_id',
          max_concurrency: 1,
          start_from_beginning: true,
          max_bytes_per_partition: 524_288,
          min_bytes: 1,
          max_wait_time: 5,
          force_encoding: nil,
          delivery: 'batch',
          session_timeout: 300,
          offset_commit_interval: 10,
          offset_commit_threshold: 0,
          offset_retention_time: nil,
          heartbeat_interval: 10,
          handler: 'ConsumerTest::MyConsumer',
          use_schema_classes: nil,
          max_db_batch_size: nil,
          bulk_import_id_generator: nil,
          backfill_associations: false
        }, {
          topic: 'my_batch_consume_topic',
          group_id: 'my_batch_group_id',
          max_concurrency: 1,
          start_from_beginning: true,
          max_bytes_per_partition: 500.kilobytes,
          min_bytes: 1,
          max_wait_time: 5,
          force_encoding: nil,
          delivery: 'inline_batch',
          session_timeout: 300,
          offset_commit_interval: 10,
          offset_commit_threshold: 0,
          offset_retention_time: nil,
          heartbeat_interval: 10,
          handler: 'ConsumerTest::MyBatchConsumer',
          use_schema_classes: nil,
          max_db_batch_size: nil,
          bulk_import_id_generator: nil,
          backfill_associations: false
        }
      ],
      producer: {
        ack_timeout: 5,
        required_acks: :all,
        max_retries: 2,
        retry_backoff: 1,
        max_buffer_size: 10_000,
        max_buffer_bytesize: 10_000_000,
        compression_codec: nil,
        compression_threshold: 1,
        max_queue_size: 10_000,
        delivery_threshold: 0,
        delivery_interval: 0,
        persistent_connections: false
      }
    )
  end

  specify '#phobos_config' do
    logger1 = Logger.new(nil)
    logger2 = Logger.new(nil)
    described_class.config.reset!
    described_class.configure do
      phobos_logger logger1
      kafka do
        logger logger2
        seed_brokers 'my-seed-brokers'
        client_id 'phobos2'
        connect_timeout 30
        socket_timeout 30
        ssl.enabled(true)
        ssl.ca_certs_from_system(true)
        ssl.ca_cert('cert')
        ssl.client_cert('cert')
        ssl.client_cert_key('key')
        ssl.verify_hostname(false)
        sasl.enabled true
        sasl.gssapi_principal 'gssapi_principal'
        sasl.gssapi_keytab 'gssapi_keytab'
        sasl.plain_authzid 'plain_authzid'
        sasl.plain_username 'plain_username'
        sasl.plain_password 'plain_password'
        sasl.scram_username 'scram_username'
        sasl.scram_password 'scram_password'
        sasl.scram_mechanism 'scram_mechanism'
        sasl.enforce_ssl true
        sasl.oauth_token_provider 'oauth_token_provider'
      end
      consumers do
        session_timeout 30
        offset_commit_interval 5
        offset_commit_threshold 0
        heartbeat_interval 5
        backoff 5..10
      end
      producers do
        ack_timeout 3
        required_acks 1
        max_retries 1
        retry_backoff 2
        max_buffer_size 5
        max_buffer_bytesize 5
        compression_codec :snappy
        compression_threshold 2
        max_queue_size 10
        delivery_threshold 1
        delivery_interval 1
        persistent_connections true
      end
      consumer do
        class_name 'MyConfigConsumer'
        schema 'blah'
        topic 'blah'
        group_id 'myconsumerid'
        max_concurrency 1
        start_from_beginning true
        max_bytes_per_partition 10
        min_bytes 5
        max_wait_time 5
        force_encoding true
        delivery :message
        backoff 100..200
        session_timeout 10
        offset_commit_interval 13
        offset_commit_threshold 13
        offset_retention_time 13
        heartbeat_interval 13
        use_schema_classes false
      end
      consumer do
        disabled true
        class_name 'MyConfigConsumer2'
        schema 'blah2'
        topic 'blah2'
        group_id 'myconsumerid2'
        use_schema_classes false
      end
    end

    expect(described_class.config.phobos_config).
      to match(
        logger: an_instance_of(Logger),
        backoff: { min_ms: 5, max_ms: 10 },
        consumer: {
          session_timeout: 30,
          offset_commit_interval: 5,
          offset_commit_threshold: 0,
          heartbeat_interval: 5
        },
        custom_kafka_logger: logger2,
        custom_logger: logger1,
        kafka: {
          client_id: 'phobos2',
          connect_timeout: 30,
          socket_timeout: 30,
          ssl_ca_certs_from_system: true,
          ssl_ca_cert: 'cert',
          ssl_client_cert: 'cert',
          ssl_client_cert_key: 'key',
          ssl_verify_hostname: false,
          seed_brokers: ['my-seed-brokers'],
          sasl_gssapi_principal: 'gssapi_principal',
          sasl_gssapi_keytab: 'gssapi_keytab',
          sasl_plain_authzid: 'plain_authzid',
          sasl_plain_username: 'plain_username',
          sasl_plain_password: 'plain_password',
          sasl_scram_username: 'scram_username',
          sasl_scram_password: 'scram_password',
          sasl_scram_mechanism: 'scram_mechanism',
          sasl_over_ssl: true,
          sasl_oauth_token_provider: 'oauth_token_provider',
        },
        listeners: [
          {
            topic: 'blah',
            group_id: 'myconsumerid',
            max_concurrency: 1,
            start_from_beginning: true,
            max_bytes_per_partition: 10,
            min_bytes: 5,
            max_wait_time: 5,
            force_encoding: true,
            delivery: 'message',
            backoff: { min_ms: 100, max_ms: 200 },
            session_timeout: 10,
            offset_commit_interval: 13,
            offset_commit_threshold: 13,
            offset_retention_time: 13,
            heartbeat_interval: 13,
            handler: 'MyConfigConsumer',
            use_schema_classes: false,
            max_db_batch_size: nil,
            bulk_import_id_generator: nil,
            backfill_associations: false
          }
        ],
        producer: {
          ack_timeout: 3,
          required_acks: 1,
          max_retries: 1,
          retry_backoff: 2,
          max_buffer_size: 5,
          max_buffer_bytesize: 5,
          compression_codec: :snappy,
          compression_threshold: 2,
          max_queue_size: 10,
          delivery_threshold: 1,
          delivery_interval: 1,
          persistent_connections: true
        }
      )
  end

  it 'should override global configurations' do
    described_class.configure do
      consumers.bulk_import_id_generator(-> { 'global' })
      consumers.replace_associations true

      consumer do
        class_name 'MyConfigConsumer'
        schema 'blah'
        topic 'blah'
        group_id 'myconsumerid'
        bulk_import_id_generator(-> { 'consumer' })
        replace_associations false
        backfill_associations true
      end

      consumer do
        class_name 'MyConfigConsumer2'
        schema 'blah'
        topic 'blah'
        group_id 'myconsumerid'
      end
    end

    consumers = described_class.config.consumers
    expect(consumers.replace_associations).to eq(true)
    expect(consumers.bulk_import_id_generator.call).to eq('global')

    custom = MyConfigConsumer.config
    expect(custom[:replace_associations]).to eq(false)
    expect(custom[:bulk_import_id_generator].call).to eq('consumer')
    expect(custom[:backfill_associations]).to eq(true)

    default = MyConfigConsumer2.config
    expect(default[:replace_associations]).to eq(true)
    expect(default[:bulk_import_id_generator].call).to eq('global')
    expect(default[:backfill_associations]).to eq(false)

  end
end
