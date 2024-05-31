# frozen_string_literal: true

require 'fig_tree'
require_relative '../metrics/mock'
require_relative '../tracing/mock'
require 'active_support/core_ext/object'

# :nodoc:
module Deimos # rubocop:disable Metrics/ModuleLength
  include FigTree

  # :nodoc:
  after_configure do
    if self.config.schema.use_schema_classes
      load_generated_schema_classes
    end
    generate_key_schemas
    validate_outbox_backend if self.config.producers.backend == :outbox
  end

  class << self

    def generate_key_schemas
      Deimos.karafka_configs.each do |config|
        transcoder = config.deserializers[:key]

        if transcoder.respond_to?(:key_field) && transcoder.key_field
          transcoder.backend = Deimos.schema_backend(schema: config.schema,
                                                     namespace: config.namespace)
          transcoder.backend.generate_key_schema(transcoder.key_field)
        end
      end
    end

    # Loads generated classes
    # @return [void]
    def load_generated_schema_classes
      if Deimos.config.schema.generated_class_path.nil?
        raise 'Cannot use schema classes without schema.generated_class_path. Please provide a directory.'
      end

      Dir["./#{Deimos.config.schema.generated_class_path}/**/*.rb"].sort.each { |f| require f }
    rescue LoadError
      raise 'Cannot load schema classes. Please regenerate classes with rake deimos:generate_schema_models.'
    end

    # Ensure everything is set up correctly for the DB backend.
    # @!visibility private
    def validate_outbox_backend
      begin
        require 'activerecord-import'
      rescue LoadError
        raise 'Cannot set producers.backend to :outbox without activerecord-import! Please add it to your Gemfile.'
      end
    end
  end

  # rubocop:enable Metrics/PerceivedComplexity, Metrics/AbcSize

  define_settings do
    setting :logger, removed: 'Use "logger" in Karafka setup block.'
    setting :payload_log, removed: 'Use topic.payload_log in Karafka settings'
    setting :phobos_logger, removed: 'Separate logger for Phobos is no longer supported'

    setting :kafka do
      setting :logger, removed: "Karafka uses Rails logger by default"
      setting :seed_brokers, ['localhost:9092'], removed: 'Use kafka(bootstrap.servers) in Karafka settings'
      setting :client_id, 'phobos', removed: 'Use client_id in Karafka setup block.'
      setting :connect_timeout, 15, removed: 'Use kafka(socket.connection.setup.timeout.ms) in Karafka settings'
      setting :socket_timeout, 15, removed: 'Use kafka(socket.timeout.ms) in Karafka settings'

      setting :ssl do
        setting :enabled, removed: 'Use kafka(security.protocol=ssl) in Karafka settings'
        setting :ca_cert, removed: 'Use kafka(ssl.ca.pem) in Karafka settings'
        setting :client_cert, removed: 'Use kafka(ssl.certificate.pem) in Karafka settings'
        setting :client_cert_key, removed: 'Use kafka(ssl.key.pem) in Karafka settings'
        setting :verify_hostname, removed: 'Use kafka(ssl.endpoint.identification.algorithm=https) in Karafka settings'
        setting :ca_certs_from_system, removed: 'Should not be necessary with librdkafka.'
      end

      setting :sasl do
        setting :enabled, removed: 'Use kafka(security.protocol=sasl_ssl or sasl_plaintext) in Karafka settings'
        setting :gssapi_principal, removed: 'Use kafka(sasl.kerberos.principal) in Karafka settings'
        setting :gssapi_keytab, removed: 'Use kafka(sasl.kerberos.keytab) in Karafka settings'
        setting :plain_authzid, removed: 'No longer needed with rdkafka'
        setting :plain_username, removed: 'Use kafka(sasl.username) in Karafka settings'
        setting :plain_password, removed: 'Use kafka(sasl.password) in Karafka settings'
        setting :scram_username, removed: 'Use kafka(sasl.username) in Karafka settings'
        setting :scram_password, removed: 'Use kafka(sasl.password) in Karafka settings'
        setting :scram_mechanism, removed: 'Use kafka(sasl.mechanisms) in Karafka settings'
        setting :enforce_ssl, removed: 'Use kafka(security.protocol=sasl_ssl) in Karafka settings'
        setting :oauth_token_provider, removed: 'See rdkafka configs for details'
      end
    end

    setting :consumers do
      setting :reraise_errors, removed: 'Use topic.reraise_errors in Karafka settings'
      setting :report_lag, removed: "Use Karafka's built in lag reporting"
      setting(:fatal_error, removed: "Use topic.fatal_error in Karafka settings")
      setting(:bulk_import_id_generator, removed: "Use topic.bulk_import_id_generator in Karafka settings")
      setting :save_associations_first, removed: "Use topic.save_associations_first"
      setting :replace_associations, removed: "Use topic.replace_associations in Karafka settings"
    end

    setting :producers do
      setting :ack_timeout, removed: "Not supported in rdkafka"
      setting :required_acks, 1, removed: "Use kafka(request.required.acks) in Karafka settings"
      setting :max_retries, removed: "Use kafka(message.send.max.retries) in Karafka settings"
      setting :retry_backoff, removed: "Use kafka(retry.backoff.ms) in Karafka settings"
      setting :max_buffer_size, removed: "Not relevant with Karafka. You may want to see the queue.buffering.max.messages setting."
      setting :max_buffer_bytesize, removed: "Not relevant with Karafka."
      setting :compression_codec, removed: "Use kafka(compression.codec) in Karafka settings"
      setting :compression_threshold, removed: "Not supported in Karafka."
      setting :max_queue_size, removed: "Not relevant to Karafka."
      setting :delivery_threshold, removed: "Not relevant to Karafka."
      setting :delivery_interval, removed: "Not relevant to Karafka."
      setting :persistent_connections, removed: "Karafka connections are always persistent."
      setting :schema_namespace, removed: "Use topic.namespace in Karafka settings"

      # Add a prefix to all topic names. This can be useful if you're using
      # the same Kafka broker for different environments that are producing
      # the same topics.
      # @return [String]
      setting :topic_prefix

      # Disable all actual message producing. Generally more useful to use
      # the `disable_producers` method instead.
      # @return [Boolean]
      setting :disabled

      # Currently can be set to :db, :kafka, or :kafka_async. If using Kafka
      # directly, a good pattern is to set to async in your user-facing app, and
      # sync in your consumers or delayed workers.
      # @return [Symbol]
      setting :backend, :kafka_async
    end

    setting :schema do

      # Backend class to use when encoding/decoding messages.
      setting :backend, :mock

      # URL of the Confluent schema registry.
      # @return [String]
      setting :registry_url, 'http://localhost:8081'

      # Basic Auth user.
      # @return [String]
      setting :user

      # Basic Auth password.
      # @return [String]
      setting :password

      # Local path to look for schemas in.
      # @return [String]
      setting :path

      # Local path for schema classes to be generated in.
      # @return [String]
      setting :generated_class_path, 'app/lib/schema_classes'

      # Set to true to use the generated schema classes in your application.
      # @return [Boolean]
      setting :use_schema_classes

      # Set to false to generate child schemas as their own files.
      # @return [Boolean]
      setting :nest_child_schemas, true

      # Set to true to generate folders matching the last part of the schema namespace.
      # @return [Boolean]
      setting :use_full_namespace, false

      # Use this option to reduce nesting when using use_full_namespace.
      # For example: { 'com.mycompany.suborg' => 'SchemaClasses' }
      # would replace a prefixed with the given key with the module name SchemaClasses.
      # @return [Hash]
      setting :schema_namespace_map, {}
    end

    # The configured metrics provider.
    # @return [Metrics::Provider]
    setting :metrics, default_proc: proc { Metrics::Mock.new }

    # The configured tracing / APM provider.
    # @return [Tracing::Provider]
    setting :tracer, default_proc: proc { Tracing::Mock.new }

    setting :outbox do

      # @return [Logger]
      setting :logger, default_proc: proc { Karafka.logger }

      # @return [Symbol|Array<String>] A list of topics to log all messages, or
      # :all to log all topics.
      setting :log_topics, []

      # @return [Symbol|Array<String>] A list of topics to compact messages for
      # before sending, or :all to compact all keyed messages.
      setting :compact_topics, []

    end

    setting :db_producer do
      setting :logger, removed: "Use outbox.logger"
      setting :log_topics, removed: "Use outbox.log_topics"
      setting :compact_topics, removed: "Use outbox.compact_topics"
    end

    setting_object :producer do
      setting :class_name, removed: "Use topic.producer_class in Karafka settings."
      setting :topic, removed: "Use Karafka settings."
      setting :schema, removed: "Use topic.schema(schema:) in Karafka settings."
      setting :namespace, removed: "Use topic.schema(namespace:) in Karafka settings."
      setting :key_config, removed: "Use topic.schema(key_config:) in Karafka settings."
      setting :use_schema_classes, removed: "Use topic.schema(use_schema_classes:) in Karafka settings."
    end

    setting_object :consumer do
      setting :class_name, removed: "Use topic.consumer in Karafka settings."
      setting :topic, removed: "Use Karafka settings."
      setting :schema, removed: "Use topic.schema(schema:) in Karafka settings."
      setting :namespace, removed: "Use topic.schema(namespace:) in Karafka settings."
      setting :key_config, removed: "Use topic.schema(key_config:) in Karafka settings."
      setting :disabled, removed: "Use topic.active in Karafka settings."
      setting :use_schema_classes, removed: "Use topic.use_schema_classes in Karafka settings."
      setting :max_db_batch_size, removed: "Use topic.max_db_batch_size in Karafka settings."
      setting :bulk_import_id_column, removed: "Use topic.bulk_import_id_column in Karafka settings."
      setting :replace_associations, removed: "Use topic.replace_associations in Karafka settings."
      setting :bulk_import_id_generator, removed: "Use topic.bulk_import_id_generator in Karafka settings."
      setting :save_associations_first, removed: "Use topic.save_associations_first"
      setting :group_id, removed: "Use kafka(group.id) in Karafka settings."
      setting :max_concurrency, removed: "Use Karafka's 'config.concurrency' in the setup block."
      setting :start_from_beginning, removed: "Use initial_offset in the setup block, or kafka(auto.offset.reset) in topic settings."
      setting :max_bytes_per_partition, removed: "Use max_messages in the setup block."
      setting :min_bytes, removed: "Not supported in Karafka."
      setting :max_wait_time, removed: "Use max_wait_time in the setup block."
      setting :force_encoding, removed: "Not supported with Karafka."
      setting :delivery, :batch, removed: "Use batch: true/false in Karafka topic configs."
      setting :backoff, removed: "Use kafka(retry.backoff.ms) and retry.backoff.max.ms in Karafka settings."
      setting :session_timeout, removed: "Use kafka(session.timeout.ms) in Karafka settings."
      setting :offset_commit_interval, removed: "Use kafka(auto.commit.interval.ms) in Karafka settings."
      setting :offset_commit_threshold, removed: "Not supported with Karafka."
      setting :offset_retention_time, removed: "Not supported with Karafka."
      setting :heartbeat_interval, removed: "Use kafka(heartbeat.interval.ms) in Karafka settings."
    end

    setting_object :db_poller do
      # Mode to use for querying - :time_based (via updated_at) or :state_based.
      setting :mode, :time_based
      # Producer class to use for the poller.
      setting :producer_class, nil
      # How often to run the poller, in seconds. If the poll takes longer than this
      # time, it will run again immediately and the timeout
      # will be pushed to the next e.g. 1 minute.
      setting :run_every, 60
      # The number of times to retry production when encountering a *non-Kafka* error. Set to nil
      # for infinite retries.
      setting :retries, 1
      # If true, rather than shutting down when finding a message that is too large, log an
      # error and skip it.
      setting :skip_too_large_messages, false
      # Amount of time, in seconds, to wait before catching updates, to allow transactions
      # to complete but still pick up the right records. Should only be set for time-based mode.
      setting :delay_time, 2
      # Column to use to find updates. Must have an index on it.
      setting :timestamp_column, :updated_at

      # If true, dump the full table rather than incremental changes. Should
      # only be used for very small tables. Time-based only.
      setting :full_table, false
      # If false, start from the current time instead of the beginning of time
      # if this is the first time running the poller. Time-based only.
      setting :start_from_beginning, true

      # Column to set once publishing is complete - state-based only.
      setting :state_column
      # Column to update with e.g. published_at. State-based only.
      setting :publish_timestamp_column
      # Value to set the state_column to once published - state-based only.
      setting :published_state
      # Value to set the state_column to if publishing fails - state-based only.
      setting :failed_state

      # Inherited poller class name to use for publishing to multiple kafka topics from a single poller
      setting :poller_class, nil
    end

  end
end
