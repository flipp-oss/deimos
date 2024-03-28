# frozen_string_literal: true

require 'fig_tree'
require_relative 'metrics/mock'
require_relative 'tracing/mock'
require 'active_support/core_ext/object'

# :nodoc:
module Deimos # rubocop:disable Metrics/ModuleLength
  include FigTree

  # :nodoc:
  after_configure do
    if self.config.schema.use_schema_classes
      load_generated_schema_classes
    end
    self.config.producer_objects.each do |producer|
      configure_producer_or_consumer(producer)
    end
    self.config.consumer_objects.each do |consumer|
      configure_producer_or_consumer(consumer)
    end
    validate_db_backend if self.config.producers.backend == :db
  end

  class << self

    # @param topic [String]
    # @param key [Symbol]
    # @return [Object]
    def consumer_config(topic, key)
      self.config.consumer_objects.find { |o| o.topic == topic }[key]
    end

    # @param handler_class [Class]
    # @return [FigTree::ConfigStruct]
    def topic_for_consumer(handler_class)
      self.config.consumer_objects.find { |o| o.class_name.constantize == handler_class}.topic
    end

    # @param topic [String]
    # @param key [Symbol]
    # @return [Object]
    def producer_config(topic, key)
      self.config.producer_objects.find { |o| o.topic == topic }[key]
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
      if Deimos.config.producers.required_acks != :all
        raise 'Cannot set producers.backend to :db unless producers.required_acks is set to ":all"!'
      end
    end

    # @!visibility private
    # @param kafka_config [FigTree::ConfigStruct]
    # rubocop:disable  Metrics/PerceivedComplexity, Metrics/AbcSize
    def configure_producer_or_consumer(kafka_config)
      klass = kafka_config.class_name.constantize
      klass.class_eval do
        if kafka_config.respond_to?(:bulk_import_id_column) # consumer
          klass.config.merge!(
            batch: kafka_config.batch,
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
  end

  # rubocop:enable Metrics/PerceivedComplexity, Metrics/AbcSize

  define_settings do

    # @return [Logger]
    setting :logger, Logger.new(STDOUT)

    # @return [Symbol]
    setting :payload_log, :full

    setting :consumers do

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
      # Set to true to ignore the consumer in the config and not actually start up a handler.
      # @return [Boolean]
      setting :disabled, false
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
