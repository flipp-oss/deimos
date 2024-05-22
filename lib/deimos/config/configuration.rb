# frozen_string_literal: true

require 'fig_tree'
require_relative 'karafka'
require_relative '../metrics/mock'
require_relative '../tracing/mock'
require 'active_support/core_ext/object'

# :nodoc:
module Deimos # rubocop:disable Metrics/ModuleLength
  include FigTree

  # :nodoc:
  after_configure do
    Deimos::KarafkaConfig.configure_karafka(self.config)
    if self.config.schema.use_schema_classes
      load_generated_schema_classes
    end
    generate_key_schemas
    validate_db_backend if self.config.producers.backend == :db
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
    def validate_db_backend
      begin
        require 'activerecord-import'
      rescue LoadError
        raise 'Cannot set producers.backend to :db without activerecord-import! Please add it to your Gemfile.'
      end
    end
  end

  # rubocop:enable Metrics/PerceivedComplexity, Metrics/AbcSize

  define_settings do

    # If set, auto-set up Karafka based on legacy settings.
    setting :legacy_mode, false

    # @return [Logger]
    setting :logger, removed: 'Use "logger" in Karafka setup block.'

    # @return [Symbol]
    setting :payload_log, removed: 'Use topic.payload_log in Karafka settings'

    # @return [Logger]
    setting :phobos_logger, removed: 'Separate logger for Phobos is no longer supported'

    setting :kafka do
     # @return [Logger]
      setting :logger, removed: "Karafka uses Rails logger by default"

      # URL of the seed broker.
      # @return [Array<String>]
      setting :seed_brokers, ['localhost:9092'], removed: 'Use config(metadata.broker.list) in Karafka settings'

      # Identifier for this application.
      # @return [String]
      setting :client_id, 'phobos', removed: 'Use client_id in Karafka setup block.'

      # The socket timeout for connecting to the broker, in seconds.
      # @return [Integer]
      setting :connect_timeout, 15, removed: 'Use config(socket.connection.setup.timeout.ms) in Karafka settings'

      # The socket timeout for reading and writing to the broker, in seconds.
      # @return [Integer]
      setting :socket_timeout, 15, removed: 'Use config(socket.timeout.ms) in Karafka settings'

      setting :ssl do
        # Whether SSL is enabled on the brokers.
        # @return [Boolean]
        setting :enabled, removed: 'Use config(security.protocol=ssl) in Karafka settings'

        # a PEM encoded CA cert, a file path to the cert, or an Array of certs,
        # to use with an SSL connection.
        # @return [String|Array<String>]
        setting :ca_cert, removed: 'Use config(ssl.ca.pem) in Karafka settings'

        # a PEM encoded client cert to use with an SSL connection, or a file path
        # to the cert.
        # @return [String]
        setting :client_cert, removed: 'Use config(ssl.certificate.pem) in Karafka settings'

        # a PEM encoded client cert key to use with an SSL connection.
        # @return [String]
        setting :client_cert_key, removed: 'Use config(ssl.key.pem) in Karafka settings'

        # Verify certificate hostname if supported (ruby >= 2.4.0)
        setting :verify_hostname, removed: 'Use config(ssl.endpoint.identification.algorithm=https) in Karafka settings'

        # Use CA certs from system. This is useful to have enabled for Confluent Cloud
        # @return [Boolean]
        setting :ca_certs_from_system, removed: 'Should not be necessary with librdkafka.'
      end

      setting :sasl do
        # Whether SASL is enabled on the brokers.
        # @return [Boolean]
        setting :enabled, removed: 'Use config(security.protocol=sasl_ssl or sasl_plaintext) in Karafka settings'

        # A KRB5 principal.
        # @return [String]
        setting :gssapi_principal, removed: 'Use config(sasl.kerberos.principal) in Karafka settings'

        # A KRB5 keytab filepath.
        # @return [String]
        setting :gssapi_keytab, removed: 'Use config(sasl.kerberos.keytab) in Karafka settings'

        # Plain authorization ID. It needs to default to '' in order for it to work.
        # This is because Phobos expects it to be truthy for using plain SASL.
        # @return [String]
        setting :plain_authzid, removed: 'No longer needed with rdkafka'

        # Plain username.
        # @return [String]
        setting :plain_username, removed: 'Use config(sasl.username) in Karafka settings'

        # Plain password.
        # @return [String]
        setting :plain_password, removed: 'Use config(sasl.password) in Karafka settings'

        # SCRAM username.
        # @return [String]
        setting :scram_username, removed: 'Use config(sasl.username) in Karafka settings'

        # SCRAM password.
        # @return [String]
        setting :scram_password, removed: 'Use config(sasl.password) in Karafka settings'

        # Scram mechanism, either "sha256" or "sha512".
        # @return [String]
        setting :scram_mechanism, removed: 'Use config(sasl.mechanisms) in Karafka settings'

        # Whether to enforce SSL with SASL.
        # @return [Boolean]
        setting :enforce_ssl, removed: 'Use config(security.protocol=sasl_ssl) in Karafka settings'

        # OAuthBearer Token Provider instance that implements
        # method token. See {Sasl::OAuth#initialize}.
        # @return [Object]
        setting :oauth_token_provider, removed: 'See rdkafka configs for details'
      end
    end

    setting :consumers do

      # By default, consumer errors will be consumed and logged to
      # the metrics provider.
      # Set this to true to force the error to be raised.
      # @return [Boolean]
      setting :reraise_errors, removed: 'Use topic.reraise_errors in Karafka settings'

      # @return [Boolean]
      setting :report_lag, removed: "Use Karafka's built in lag reporting"

      # Block taking an exception, payload and metadata and returning
      # true if this should be considered a fatal error and false otherwise.
      # Not needed if reraise_errors is set to true.
      # @return [Block]
      setting(:fatal_error, removed: "Use topic.fatal_error in Karafka settings")

      # The default function to generate a bulk ID for bulk consumers
      # @return [Block]
      setting(:bulk_import_id_generator, removed: "Use topic.bulk_import_id_generator in Karafka settings")

      # If true, multi-table consumers will blow away associations rather than appending to them.
      # Applies to all consumers unless specified otherwise
      # @return [Boolean]
      setting :replace_associations, removed: "Use topic.replace_associations in Karafka settings"
    end

    setting :producers do
      # Number of seconds a broker can wait for replicas to acknowledge
      # a write before responding with a timeout.
      # @return [Integer]
      setting :ack_timeout, removed: "Not supported in rdkafka"

      # Number of replicas that must acknowledge a write, or `:all`
      # if all in-sync replicas must acknowledge.
      # @return [Integer|Symbol]
      setting :required_acks, 1, removed: "Use config(request.required.acks) in Karafka settings"

      # Number of retries that should be attempted before giving up sending
      # messages to the cluster. Does not include the original attempt.
      # @return [Integer]
      setting :max_retries, removed: "Use config(message.send.max.retries) in Karafka settings"

      # Number of seconds to wait between retries.
      # @return [Integer]
      setting :retry_backoff, removed: "Use config(retry.backoff.ms) in Karafka settings"

      # Number of messages allowed in the buffer before new writes will
      # raise {BufferOverflow} exceptions.
      # @return [Integer]
      setting :max_buffer_size, removed: "Not relevant with Karafka. You may want to see the queue.buffering.max.messages setting."

      # Maximum size of the buffer in bytes. Attempting to produce messages
      # when the buffer reaches this size will result in {BufferOverflow} being raised.
      # @return [Integer]
      setting :max_buffer_bytesize, removed: "Not relevant with Karafka."

      # Name of the compression codec to use, or nil if no compression should be performed.
      # Valid codecs: `:snappy` and `:gzip`
      # @return [Symbol]
      setting :compression_codec, removed: "Use config(compression.codec) in Karafka settings"

      # Number of messages that needs to be in a message set before it should be compressed.
      # Note that message sets are per-partition rather than per-topic or per-producer.
      # @return [Integer]
      setting :compression_threshold, removed: "Not supported in Karafka."

      # Maximum number of messages allowed in the queue. Only used for async_producer.
      # @return [Integer]
      setting :max_queue_size, removed: "Not relevant to Karafka."

      # If greater than zero, the number of buffered messages that will automatically
      # trigger a delivery. Only used for async_producer.
      # @return [Integer]
      setting :delivery_threshold, removed: "Not relevant to Karafka."

      # if greater than zero, the number of seconds between automatic message
      # deliveries. Only used for async_producer.
      # @return [Integer]
      setting :delivery_interval, removed: "Not relevant to Karafka."

      # Set this to true to keep the producer connection between publish calls.
      # This can speed up subsequent messages by around 30%, but it does mean
      # that you need to manually call sync_producer_shutdown before exiting,
      # similar to async_producer_shutdown.
      # @return [Boolean]
      setting :persistent_connections, removed: "Karafka connections are always persistent."

      # Default namespace for all producers. Can remain nil. Individual
      # producers can override.
      # @return [String]
      setting :schema_namespace, removed: "Use topic.namespace in Karafka settings"

      # Add a prefix to all topic names. This can be useful if you're using
      # the same Kafka broker for different environments that are producing
      # the same topics.
      # @return [String]
      setting :topic_prefix

      # Disable all actual message producing. Generally more useful to use
      # the `disable_producers` method instead.
      # @return [Boolean]
      setting :disabled, removed: "No longer supported"

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

    setting :db_producer do

      # @return [Logger]
      setting :logger, default_proc: proc { Deimos.config.logger }

      # @return [Symbol|Array<String>] A list of topics to log all messages, or
      # :all to log all topics.
      setting :log_topics, []

      # @return [Symbol|Array<String>] A list of topics to compact messages for
      # before sending, or :all to compact all keyed messages.
      setting :compact_topics, []

    end

    setting_object :producer do
      # Producer class.
      # @return [String]
      setting :class_name, removed: "Use topic.producer_class in Karafka settings."
      # Topic to produce to.
      # @return [String]
      setting :topic, removed: "Use Karafka settings."
      # Schema of the data in the topic.
      # @return [String]
      setting :schema, removed: "Use topic.schema(schema:) in Karafka settings."
      # Optional namespace to access the schema.
      # @return [String]
      setting :namespace, removed: "Use topic.schema(namespace:) in Karafka settings."
      # Key configuration (see docs).
      # @return [Hash]
      setting :key_config, removed: "Use topic.schema(key_config:) in Karafka settings."
      # Configure the usage of generated schema classes for this producer
      # @return [Boolean]
      setting :use_schema_classes, removed: "Use topic.schema(use_schema_classes:) in Karafka settings."
    end

    setting_object :consumer do
      # Consumer class.
      # @return [String]
      setting :class_name, removed: "Use topic.consumer in Karafka settings."
      # Topic to read from.
      # @return [String]
      setting :topic, removed: "Use Karafka settings."
      # Schema of the data in the topic.
      # @return [String]
      setting :schema, removed: "Use topic.schema(schema:) in Karafka settings."
      # Optional namespace to access the schema.
      # @return [String]
      setting :namespace, removed: "Use topic.schema(namespace:) in Karafka settings."
      # Key configuration (see docs).
      # @return [Hash]
      setting :key_config, removed: "Use topic.schema(key_config:) in Karafka settings."
      # Set to true to ignore the consumer in the config and not actually start up a handler.
      # @return [Boolean]
      setting :disabled, removed: "Use topic.active in Karafka settings."
      # Deliver messages in batches rather than one at a time.
      setting :batch, false
      # Configure the usage of generated schema classes for this consumer
      # @return [Boolean]
      setting :use_schema_classes
      # Optional maximum limit for batching database calls to reduce the load on the db.
      # @return [Integer]
      setting :max_db_batch_size
      # Column to use for bulk imports, for multi-table feature.
      # @return [String]
      setting :bulk_import_id_column, :bulk_import_id
      # If true, multi-table consumers will blow away associations rather than appending to them.
      # @return [Boolean]
      setting :replace_associations, nil

      # The default function to generate a bulk ID for this consumer
      # Uses the consumers proc defined in the consumers config by default unless
      # specified for individual consumers
      # @return [Block]
      setting :bulk_import_id_generator, nil

      # These are the phobos "listener" configs. See CONFIGURATION.md for more
      # info.
      setting :group_id, removed: "Use config(group.id) in Karafka settings."
      setting :max_concurrency, removed: "Use Karafka's 'config.concurrency' in the setup block."
      setting :start_from_beginning, removed: "Use initial_offset in the setup block, or config(auto.offset.reset) in topic settings."
      setting :max_bytes_per_partition, removed: "Use max_messages in the setup block."
      setting :min_bytes, removed: "Not supported in Karafka."
      setting :max_wait_time, removed: "Use max_wait_time in the setup block."
      setting :force_encoding, removed: "Not supported with Karafka."
      setting :delivery, :batch, removed: "Use batch: true/false in Karafka topic configs."
      setting :backoff, removed: "Use config(retry.backoff.ms) and retry.backoff.max.ms in Karafka settings."
      setting :session_timeout, removed: "Use config(session.timeout.ms) in Karafka settings."
      setting :offset_commit_interval, removed: "Use config(auto.commit.interval.ms) in Karafka settings."
      setting :offset_commit_threshold, removed: "Not supported with Karafka."
      setting :offset_retention_time, removed: "Not supported with Karafka."
      setting :heartbeat_interval, removed: "Use config(heartbeat.interval.ms) in Karafka settings."
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
