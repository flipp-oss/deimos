# frozen_string_literal: true

require 'fig_tree'
require_relative 'phobos_config'
require_relative '../metrics/mock'
require_relative '../tracing/mock'
require 'active_support/core_ext/numeric'

# :nodoc:
module Deimos # rubocop:disable Metrics/ModuleLength
  include FigTree

  # :nodoc:
  class FigTree::ConfigStruct
    include Deimos::PhobosConfig
  end

  # :nodoc:
  after_configure do
    Phobos.configure(self.config.phobos_config)
    if self.config.schema.use_schema_classes
      load_generated_schema_classes
    end
    self.config.producer_objects.each do |producer|
      configure_producer_or_consumer(producer)
    end
    self.config.consumer_objects.each do |consumer|
      configure_producer_or_consumer(consumer)
    end
    validate_consumers
    validate_db_backend if self.config.producers.backend == :db
  end

  # Loads generated classes
  # @return [void]
  def self.load_generated_schema_classes
    if Deimos.config.schema.generated_class_path.nil?
      raise 'Cannot use schema classes without schema.generated_class_path. Please provide a directory.'
    end

    Dir["./#{Deimos.config.schema.generated_class_path}/**/*.rb"].sort.each { |f| require f }
  rescue LoadError
    raise 'Cannot load schema classes. Please regenerate classes with rake deimos:generate_schema_models.'
  end

  # Ensure everything is set up correctly for the DB backend.
  # @!visibility private
  def self.validate_db_backend
    begin
      require 'activerecord-import'
    rescue LoadError
      raise 'Cannot set producers.backend to :db without activerecord-import! Please add it to your Gemfile.'
    end
    if Deimos.config.producers.required_acks != :all
      raise 'Cannot set producers.backend to :db unless producers.required_acks is set to ":all"!'
    end
  end

  # Validate that consumers are configured correctly, including their
  # delivery mode.
  # @!visibility private
  def self.validate_consumers
    Phobos.config.listeners.each do |listener|
      handler_class = listener.handler.constantize
      delivery = listener.delivery

      next unless handler_class < Deimos::Consumer

      # Validate that each consumer implements the correct method for its type
      if delivery == 'inline_batch'
        if handler_class.instance_method(:consume_batch).owner == Deimos::Consume::BatchConsumption
          raise "BatchConsumer #{listener.handler} does not implement `consume_batch`"
        end
      elsif handler_class.instance_method(:consume).owner == Deimos::Consume::MessageConsumption
        raise "Non-batch Consumer #{listener.handler} does not implement `consume`"
      end
    end
  end

  # @!visibility private
  # @param kafka_config [FigTree::ConfigStruct]
  # rubocop:disable  Metrics/PerceivedComplexity, Metrics/AbcSize
  def self.configure_producer_or_consumer(kafka_config)
    klass = kafka_config.class_name.constantize
    klass.class_eval do
      topic(kafka_config.topic) if kafka_config.topic.present? && klass.respond_to?(:topic)
      schema(kafka_config.schema) if kafka_config.schema.present?
      namespace(kafka_config.namespace) if kafka_config.namespace.present?
      key_config(**kafka_config.key_config) if kafka_config.key_config.present?
      schema_class_config(kafka_config.use_schema_classes) if kafka_config.use_schema_classes.present?
      if kafka_config.respond_to?(:bulk_import_id_column) # consumer
        klass.config.merge!(
          bulk_import_id_column: kafka_config.bulk_import_id_column,
          replace_associations: if kafka_config.replace_associations.nil?
                                  Deimos.config.consumers.replace_associations
                                else
                                  kafka_config.replace_associations
                                end,
          bulk_import_id_generator: kafka_config.bulk_import_id_generator ||
            Deimos.config.consumers.bulk_import_id_generator
        )
      end
    end
  end
  # rubocop:enable Metrics/PerceivedComplexity, Metrics/AbcSize

  define_settings do

    # @return [Logger]
    setting :logger, Logger.new(STDOUT)

    # @return [Symbol]
    setting :payload_log, :full

    # @return [Logger]
    setting :phobos_logger, default_proc: proc { Deimos.config.logger.clone }

    setting :kafka do

      # @return [Logger]
      setting :logger, default_proc: proc { Deimos.config.logger.clone }

      # URL of the seed broker.
      # @return [Array<String>]
      setting :seed_brokers, ['localhost:9092']

      # Identifier for this application.
      # @return [String]
      setting :client_id, 'phobos'

      # The socket timeout for connecting to the broker, in seconds.
      # @return [Integer]
      setting :connect_timeout, 15

      # The socket timeout for reading and writing to the broker, in seconds.
      # @return [Integer]
      setting :socket_timeout, 15

      setting :ssl do
        # Whether SSL is enabled on the brokers.
        # @return [Boolean]
        setting :enabled

        # a PEM encoded CA cert, a file path to the cert, or an Array of certs,
        # to use with an SSL connection.
        # @return [String|Array<String>]
        setting :ca_cert

        # a PEM encoded client cert to use with an SSL connection, or a file path
        # to the cert.
        # @return [String]
        setting :client_cert

        # a PEM encoded client cert key to use with an SSL connection.
        # @return [String]
        setting :client_cert_key

        # Verify certificate hostname if supported (ruby >= 2.4.0)
        setting :verify_hostname, true

        # Use CA certs from system. This is useful to have enabled for Confluent Cloud
        # @return [Boolean]
        setting :ca_certs_from_system, false
      end

      setting :sasl do
        # Whether SASL is enabled on the brokers.
        # @return [Boolean]
        setting :enabled

        # A KRB5 principal.
        # @return [String]
        setting :gssapi_principal

        # A KRB5 keytab filepath.
        # @return [String]
        setting :gssapi_keytab

        # Plain authorization ID. It needs to default to '' in order for it to work.
        # This is because Phobos expects it to be truthy for using plain SASL.
        # @return [String]
        setting :plain_authzid, ''

        # Plain username.
        # @return [String]
        setting :plain_username

        # Plain password.
        # @return [String]
        setting :plain_password

        # SCRAM username.
        # @return [String]
        setting :scram_username

        # SCRAM password.
        # @return [String]
        setting :scram_password

        # Scram mechanism, either "sha256" or "sha512".
        # @return [String]
        setting :scram_mechanism

        # Whether to enforce SSL with SASL.
        # @return [Boolean]
        setting :enforce_ssl

        # OAuthBearer Token Provider instance that implements
        # method token. See {Sasl::OAuth#initialize}.
        # @return [Object]
        setting :oauth_token_provider
      end
    end

    setting :consumers do

      # Number of seconds after which, if a client hasn't contacted the Kafka cluster,
      # it will be kicked out of the group.
      # @return [Integer]
      setting :session_timeout, 300

      # Interval between offset commits, in seconds.
      # @return [Integer]
      setting :offset_commit_interval, 10

      # Number of messages that can be processed before their offsets are committed.
      # If zero, offset commits are not triggered by message processing
      # @return [Integer]
      setting :offset_commit_threshold, 0

      # Interval between heartbeats; must be less than the session window.
      # @return [Integer]
      setting :heartbeat_interval, 10

      # Minimum and maximum number of milliseconds to back off after a consumer
      # error.
      setting :backoff, (1000..60_000)

      # By default, consumer errors will be consumed and logged to
      # the metrics provider.
      # Set this to true to force the error to be raised.
      # @return [Boolean]
      setting :reraise_errors

      # @return [Boolean]
      setting :report_lag

      # Block taking an exception, payload and metadata and returning
      # true if this should be considered a fatal error and false otherwise.
      # Not needed if reraise_errors is set to true.
      # @return [Block]
      setting(:fatal_error, proc { false })

      # The default function to generate a bulk ID for bulk consumers
      # @return [Block]
      setting(:bulk_import_id_generator, proc { SecureRandom.uuid })

      # If true, multi-table consumers will blow away associations rather than appending to them.
      # Applies to all consumers unless specified otherwise
      # @return [Boolean]
      setting :replace_associations, true
    end

    setting :producers do
      # Number of seconds a broker can wait for replicas to acknowledge
      # a write before responding with a timeout.
      # @return [Integer]
      setting :ack_timeout, 5

      # Number of replicas that must acknowledge a write, or `:all`
      # if all in-sync replicas must acknowledge.
      # @return [Integer|Symbol]
      setting :required_acks, 1

      # Number of retries that should be attempted before giving up sending
      # messages to the cluster. Does not include the original attempt.
      # @return [Integer]
      setting :max_retries, 2

      # Number of seconds to wait between retries.
      # @return [Integer]
      setting :retry_backoff, 1

      # Number of messages allowed in the buffer before new writes will
      # raise {BufferOverflow} exceptions.
      # @return [Integer]
      setting :max_buffer_size, 10_000

      # Maximum size of the buffer in bytes. Attempting to produce messages
      # when the buffer reaches this size will result in {BufferOverflow} being raised.
      # @return [Integer]
      setting :max_buffer_bytesize, 10_000_000

      # Name of the compression codec to use, or nil if no compression should be performed.
      # Valid codecs: `:snappy` and `:gzip`
      # @return [Symbol]
      setting :compression_codec

      # Number of messages that needs to be in a message set before it should be compressed.
      # Note that message sets are per-partition rather than per-topic or per-producer.
      # @return [Integer]
      setting :compression_threshold, 1

      # Maximum number of messages allowed in the queue. Only used for async_producer.
      # @return [Integer]
      setting :max_queue_size, 10_000

      # If greater than zero, the number of buffered messages that will automatically
      # trigger a delivery. Only used for async_producer.
      # @return [Integer]
      setting :delivery_threshold, 0

      # if greater than zero, the number of seconds between automatic message
      # deliveries. Only used for async_producer.
      # @return [Integer]
      setting :delivery_interval, 0

      # Set this to true to keep the producer connection between publish calls.
      # This can speed up subsequent messages by around 30%, but it does mean
      # that you need to manually call sync_producer_shutdown before exiting,
      # similar to async_producer_shutdown.
      # @return [Boolean]
      setting :persistent_connections, false

      # Default namespace for all producers. Can remain nil. Individual
      # producers can override.
      # @return [String]
      setting :schema_namespace

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

      # Set to true to use the generated schema classes in your application
      # @return [Boolean]
      setting :use_schema_classes, false

      # Set to false to generate child schemas as their own files.
      # @return [Boolean]
      setting :nest_child_schemas, true

      # Set to true to generate folders matching the last part of the schema namespace.
      # @return [Boolean]
      setting :generate_namespace_folders, false
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
      setting :class_name
      # Topic to produce to.
      # @return [String]
      setting :topic
      # Schema of the data in the topic.
      # @return [String]
      setting :schema
      # Optional namespace to access the schema.
      # @return [String]
      setting :namespace
      # Key configuration (see docs).
      # @return [Hash]
      setting :key_config
      # Configure the usage of generated schema classes for this producer
      # @return [Boolean]
      setting :use_schema_classes
      # If true, and using the multi-table feature of ActiveRecordConsumers, replace associations
      # instead of appending to them.
      # @return [Boolean]
      setting :replace_associations
    end

    setting_object :consumer do
      # Consumer class.
      # @return [String]
      setting :class_name
      # Topic to read from.
      # @return [String]
      setting :topic
      # Schema of the data in the topic.
      # @return [String]
      setting :schema
      # Optional namespace to access the schema.
      # @return [String]
      setting :namespace
      # Key configuration (see docs).
      # @return [Hash]
      setting :key_config
      # Set to true to ignore the consumer in the Phobos config and not actually start up a
      # listener.
      # @return [Boolean]
      setting :disabled, false
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
      setting :group_id
      setting :max_concurrency, 1
      setting :start_from_beginning, true
      setting :max_bytes_per_partition, 500.kilobytes
      setting :min_bytes, 1
      setting :max_wait_time, 5
      setting :force_encoding
      setting :delivery, :batch
      setting :backoff
      setting :session_timeout, 300
      setting :offset_commit_interval, 10
      setting :offset_commit_threshold, 0
      setting :offset_retention_time
      setting :heartbeat_interval, 10
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

    deprecate 'kafka_logger', 'kafka.logger'
    deprecate 'reraise_consumer_errors', 'consumers.reraise_errors'
    deprecate 'schema_registry_url', 'schema.registry_url'
    deprecate 'seed_broker', 'kafka.seed_brokers'
    deprecate 'schema_path', 'schema.path'
    deprecate 'producer_schema_namespace', 'producers.schema_namespace'
    deprecate 'producer_topic_prefix', 'producers.topic_prefix'
    deprecate 'disable_producers', 'producers.disabled'
    deprecate 'ssl_enabled', 'kafka.ssl.enabled'
    deprecate 'ssl_ca_cert', 'kafka.ssl.ca_cert'
    deprecate 'ssl_client_cert', 'kafka.ssl.client_cert'
    deprecate 'ssl_client_cert_key', 'kafka.ssl.client_cert_key'
    deprecate 'publish_backend', 'producers.backend'
    deprecate 'report_lag', 'consumers.report_lag'

  end
end
