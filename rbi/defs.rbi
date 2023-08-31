# typed: strong
# Generates a migration for bulk import ID in consumer.
module Deimos
  include Deimos::Instrumentation
  include FigTree
  VERSION = T.let('1.22.5', T.untyped)

  sig { returns(T.class_of(Deimos::SchemaBackends::Base)) }
  def self.schema_backend_class; end

  # _@param_ `schema`
  # 
  # _@param_ `namespace`
  sig { params(schema: T.any(String, Symbol), namespace: String).returns(Deimos::SchemaBackends::Base) }
  def self.schema_backend(schema:, namespace:); end

  # _@param_ `schema`
  # 
  # _@param_ `namespace`
  # 
  # _@param_ `payload`
  # 
  # _@param_ `subject`
  sig do
    params(
      schema: String,
      namespace: String,
      payload: T::Hash[T.untyped, T.untyped],
      subject: T.nilable(String)
    ).returns(String)
  end
  def self.encode(schema:, namespace:, payload:, subject: nil); end

  # _@param_ `schema`
  # 
  # _@param_ `namespace`
  # 
  # _@param_ `payload`
  sig { params(schema: String, namespace: String, payload: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def self.decode(schema:, namespace:, payload:); end

  # Start the DB producers to send Kafka messages.
  # 
  # _@param_ `thread_count` — the number of threads to start.
  sig { params(thread_count: Integer).void }
  def self.start_db_backend!(thread_count: 1); end

  # Run a block without allowing any messages to be produced to Kafka.
  # Optionally add a list of producer classes to limit the disabling to those
  # classes.
  # 
  # _@param_ `producer_classes`
  sig { params(producer_classes: T.any(T::Array[T.class_of(BasicObject)], T.class_of(BasicObject)), block: T.untyped).void }
  def self.disable_producers(*producer_classes, &block); end

  # Are producers disabled? If a class is passed in, check only that class.
  # Otherwise check if the global disable flag is set.
  # 
  # _@param_ `producer_class`
  sig { params(producer_class: T.nilable(T.class_of(BasicObject))).returns(T::Boolean) }
  def self.producers_disabled?(producer_class = nil); end

  # Loads generated classes
  sig { void }
  def self.load_generated_schema_classes; end

  # Basically a struct to hold the message as it's processed.
  class Message
    # _@param_ `payload`
    # 
    # _@param_ `producer`
    # 
    # _@param_ `topic`
    # 
    # _@param_ `key`
    # 
    # _@param_ `partition_key`
    # 
    # _@param_ `headers`
    sig do
      params(
        payload: T::Hash[T.untyped, T.untyped],
        producer: T.class_of(BasicObject),
        topic: T.nilable(String),
        key: T.nilable(T.any(String, Integer, T::Hash[T.untyped, T.untyped])),
        headers: T.nilable(T::Hash[T.untyped, T.untyped]),
        partition_key: T.nilable(Integer)
      ).void
    end
    def initialize(payload, producer, topic: nil, key: nil, headers: nil, partition_key: nil); end

    # Add message_id and timestamp default values if they are in the
    # schema and don't already have values.
    # 
    # _@param_ `fields` — existing name fields in the schema.
    sig { params(fields: T::Array[String]).void }
    def add_fields(fields); end

    # _@param_ `encoder`
    sig { params(encoder: Deimos::SchemaBackends::Base).void }
    def coerce_fields(encoder); end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def encoded_hash; end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def to_h; end

    # _@param_ `other`
    sig { params(other: Deimos::Message).returns(T::Boolean) }
    def ==(other); end

    # _@return_ — True if this message is a tombstone
    sig { returns(T::Boolean) }
    def tombstone?; end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_accessor :payload

    sig { returns(T.any(T::Hash[T.untyped, T.untyped], String, Integer)) }
    attr_accessor :key

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_accessor :headers

    sig { returns(Integer) }
    attr_accessor :partition_key

    sig { returns(String) }
    attr_accessor :encoded_key

    sig { returns(String) }
    attr_accessor :encoded_payload

    sig { returns(String) }
    attr_accessor :topic

    sig { returns(String) }
    attr_accessor :producer_name
  end

  # Add rake task to Rails.
  class Railtie < Rails::Railtie
  end

  # Basic consumer class. Inherit from this class and override either consume
  # or consume_batch, depending on the delivery mode of your listener.
  # `consume` -> use `delivery :message` or `delivery :batch`
  # `consume_batch` -> use `delivery :inline_batch`
  class Consumer
    include Deimos::Consume::MessageConsumption
    include Deimos::Consume::BatchConsumption
    include Deimos::SharedConfig

    sig { returns(Deimos::SchemaBackends::Base) }
    def self.decoder; end

    sig { returns(Deimos::SchemaBackends::Base) }
    def self.key_decoder; end

    # Helper method to decode an encoded key.
    # 
    # _@param_ `key`
    # 
    # _@return_ — the decoded key.
    sig { params(key: String).returns(Object) }
    def decode_key(key); end

    # Helper method to decode an encoded message.
    # 
    # _@param_ `payload`
    # 
    # _@return_ — the decoded message.
    sig { params(payload: Object).returns(Object) }
    def decode_message(payload); end

    # _@param_ `batch`
    # 
    # _@param_ `metadata`
    sig { params(batch: T::Array[String], metadata: T::Hash[T.untyped, T.untyped]).void }
    def around_consume_batch(batch, metadata); end

    # Consume a batch of incoming messages.
    # 
    # _@param_ `_payloads`
    # 
    # _@param_ `_metadata`
    sig { params(_payloads: T::Array[Phobos::BatchMessage], _metadata: T::Hash[T.untyped, T.untyped]).void }
    def consume_batch(_payloads, _metadata); end

    # _@param_ `payload`
    # 
    # _@param_ `metadata`
    sig { params(payload: String, metadata: T::Hash[T.untyped, T.untyped]).void }
    def around_consume(payload, metadata); end

    # Consume incoming messages.
    # 
    # _@param_ `_payload`
    # 
    # _@param_ `_metadata`
    sig { params(_payload: String, _metadata: T::Hash[T.untyped, T.untyped]).void }
    def consume(_payload, _metadata); end
  end

  # Producer to publish messages to a given kafka topic.
  class Producer
    include Deimos::SharedConfig
    MAX_BATCH_SIZE = T.let(500, T.untyped)

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def self.config; end

    # Set the topic.
    # 
    # _@param_ `topic`
    # 
    # _@return_ — the current topic if no argument given.
    sig { params(topic: T.nilable(String)).returns(String) }
    def self.topic(topic = nil); end

    # Override the default partition key (which is the payload key).
    # Will include `payload_key` if it is part of the original payload.
    # 
    # _@param_ `_payload` — the payload being passed into the produce method.
    sig { params(_payload: T::Hash[T.untyped, T.untyped]).returns(String) }
    def self.partition_key(_payload); end

    # Publish the payload to the topic.
    # 
    # _@param_ `payload` — with an optional payload_key hash key.
    # 
    # _@param_ `topic` — if specifying the topic
    # 
    # _@param_ `headers` — if specifying headers
    sig { params(payload: T.any(T::Hash[T.untyped, T.untyped], Deimos::SchemaClass::Record), topic: String, headers: T.nilable(T::Hash[T.untyped, T.untyped])).void }
    def self.publish(payload, topic: self.topic, headers: nil); end

    # Publish a list of messages.
    # whether to publish synchronously.
    # and send immediately to Kafka.
    # 
    # _@param_ `payloads` — with optional payload_key hash key.
    # 
    # _@param_ `sync` — if given, override the default setting of
    # 
    # _@param_ `force_send` — if true, ignore the configured backend
    # 
    # _@param_ `topic` — if specifying the topic
    # 
    # _@param_ `headers` — if specifying headers
    sig do
      params(
        payloads: T::Array[T.any(T::Hash[T.untyped, T.untyped], Deimos::SchemaClass::Record)],
        sync: T.nilable(T::Boolean),
        force_send: T::Boolean,
        topic: String,
        headers: T.nilable(T::Hash[T.untyped, T.untyped])
      ).void
    end
    def self.publish_list(payloads, sync: nil, force_send: false, topic: self.topic, headers: nil); end

    # _@param_ `sync`
    # 
    # _@param_ `force_send`
    sig { params(sync: T::Boolean, force_send: T::Boolean).returns(T.class_of(Deimos::Backends::Base)) }
    def self.determine_backend_class(sync, force_send); end

    # Send a batch to the backend.
    # 
    # _@param_ `backend`
    # 
    # _@param_ `batch`
    sig { params(backend: T.class_of(Deimos::Backends::Base), batch: T::Array[Deimos::Message]).void }
    def self.produce_batch(backend, batch); end

    sig { returns(Deimos::SchemaBackends::Base) }
    def self.encoder; end

    sig { returns(Deimos::SchemaBackends::Base) }
    def self.key_encoder; end

    # Override this in active record producers to add
    # non-schema fields to check for updates
    # 
    # _@return_ — fields to check for updates
    sig { returns(T::Array[String]) }
    def self.watched_attributes; end
  end

  # ActiveRecord class to record the last time we polled the database.
  # For use with DbPoller.
  class PollInfo < ActiveRecord::Base
  end

  class MissingImplementationError < StandardError
  end

  module Backends
    # Backend which saves messages to the database instead of immediately
    # sending them.
    class Db < Deimos::Backends::Base
      # :nodoc:
      sig { params(producer_class: T.class_of(Deimos::Producer), messages: T::Array[Deimos::Message]).void }
      def self.execute(producer_class:, messages:); end

      # _@param_ `message`
      # 
      # _@return_ — the partition key to use for this message
      sig { params(message: Deimos::Message).returns(String) }
      def self.partition_key_for(message); end
    end

    # Abstract class for all publish backends.
    class Base
      # _@param_ `producer_class`
      # 
      # _@param_ `messages`
      sig { params(producer_class: T.class_of(Deimos::Producer), messages: T::Array[Deimos::Message]).void }
      def self.publish(producer_class:, messages:); end

      # _@param_ `producer_class`
      # 
      # _@param_ `messages`
      sig { params(producer_class: T.class_of(Deimos::Producer), messages: T::Array[Deimos::Message]).void }
      def self.execute(producer_class:, messages:); end
    end

    # Backend which saves messages to an in-memory hash.
    class Test < Deimos::Backends::Base
      sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
      def self.sent_messages; end

      sig { params(producer_class: T.class_of(Deimos::Producer), messages: T::Array[Deimos::Message]).void }
      def self.execute(producer_class:, messages:); end
    end

    # Default backend to produce to Kafka.
    class Kafka < Deimos::Backends::Base
      include Phobos::Producer

      # Shut down the producer if necessary.
      sig { void }
      def self.shutdown_producer; end

      # :nodoc:
      sig { params(producer_class: T.class_of(Deimos::Producer), messages: T::Array[Deimos::Message]).void }
      def self.execute(producer_class:, messages:); end
    end

    # Backend which produces to Kafka via an async producer.
    class KafkaAsync < Deimos::Backends::Base
      include Phobos::Producer

      # Shut down the producer cleanly.
      sig { void }
      def self.shutdown_producer; end

      # :nodoc:
      sig { params(producer_class: T.class_of(Deimos::Producer), messages: T::Array[Deimos::Message]).void }
      def self.execute(producer_class:, messages:); end
    end
  end

  # Represents an object which needs to inform Kafka when it is saved or
  # bulk imported.
  module KafkaSource
    extend ActiveSupport::Concern
    DEPRECATION_WARNING = T.let('The kafka_producer interface will be deprecated ' \
'in future releases. Please use kafka_producers instead.', T.untyped)

    # Send the newly created model to Kafka.
    sig { void }
    def send_kafka_event_on_create; end

    # Send the newly updated model to Kafka.
    sig { void }
    def send_kafka_event_on_update; end

    # Send a deletion (null payload) event to Kafka.
    sig { void }
    def send_kafka_event_on_destroy; end

    # Payload to send after we are destroyed.
    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def deletion_payload; end

    # :nodoc:
    module ClassMethods
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def kafka_config; end

      # _@return_ — the producers to run.
      sig { returns(T::Array[T.class_of(Deimos::ActiveRecordProducer)]) }
      def kafka_producers; end
    end
  end

  module Metrics
    # A mock Metrics wrapper which just logs the metrics
    class Mock < Deimos::Metrics::Provider
      # _@param_ `logger`
      sig { params(logger: T.nilable(Logger)).void }
      def initialize(logger = nil); end

      # :nodoc:
      sig { params(metric_name: String, options: T::Hash[T.untyped, T.untyped]).void }
      def increment(metric_name, options = {}); end

      # :nodoc:
      sig { params(metric_name: String, count: Integer, options: T::Hash[T.untyped, T.untyped]).void }
      def gauge(metric_name, count, options = {}); end

      # :nodoc:
      sig { params(metric_name: String, count: Integer, options: T::Hash[T.untyped, T.untyped]).void }
      def histogram(metric_name, count, options = {}); end

      # :nodoc:
      sig { params(metric_name: String, options: T::Hash[T.untyped, T.untyped]).void }
      def time(metric_name, options = {}); end
    end

    # A Metrics wrapper class for Datadog.
    class Datadog < Deimos::Metrics::Provider
      # _@param_ `config`
      # 
      # _@param_ `logger`
      sig { params(config: T::Hash[T.untyped, T.untyped], logger: Logger).void }
      def initialize(config, logger); end

      # :nodoc:
      sig { params(metric_name: String, options: T::Hash[T.untyped, T.untyped]).void }
      def increment(metric_name, options = {}); end

      # :nodoc:
      sig { params(metric_name: String, count: Integer, options: T::Hash[T.untyped, T.untyped]).void }
      def gauge(metric_name, count, options = {}); end

      # :nodoc:
      sig { params(metric_name: String, count: Integer, options: T::Hash[T.untyped, T.untyped]).void }
      def histogram(metric_name, count, options = {}); end

      # :nodoc:
      sig { params(metric_name: String, options: T::Hash[T.untyped, T.untyped]).void }
      def time(metric_name, options = {}); end
    end

    # Base class for all metrics providers.
    class Provider
      # Send an counter increment metric
      # 
      # _@param_ `metric_name` — The name of the counter metric
      # 
      # _@param_ `options` — Any additional options, e.g. :tags
      sig { params(metric_name: String, options: T::Hash[T.untyped, T.untyped]).void }
      def increment(metric_name, options = {}); end

      # Send an counter increment metric
      # 
      # _@param_ `metric_name` — The name of the counter metric
      # 
      # _@param_ `count`
      # 
      # _@param_ `options` — Any additional options, e.g. :tags
      sig { params(metric_name: String, count: Integer, options: T::Hash[T.untyped, T.untyped]).void }
      def gauge(metric_name, count, options = {}); end

      # Send an counter increment metric
      # 
      # _@param_ `metric_name` — The name of the counter metric
      # 
      # _@param_ `count`
      # 
      # _@param_ `options` — Any additional options, e.g. :tags
      sig { params(metric_name: String, count: Integer, options: T::Hash[T.untyped, T.untyped]).void }
      def histogram(metric_name, count, options = {}); end

      # Time a yielded block, and send a timer metric
      # 
      # _@param_ `metric_name` — The name of the metric
      # 
      # _@param_ `options` — Any additional options, e.g. :tags
      sig { params(metric_name: String, options: T::Hash[T.untyped, T.untyped]).void }
      def time(metric_name, options = {}); end
    end
  end

  # Include this module in your RSpec spec_helper
  # to stub out external dependencies
  # and add methods to use to test encoding/decoding.
  module TestHelpers
    extend ActiveSupport::Concern

    # for backwards compatibility
    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def self.sent_messages; end

    # Set the config to the right settings for a unit test
    sig { void }
    def self.unit_test!; end

    # Kafka test config with avro schema registry
    sig { void }
    def self.full_integration_test!; end

    # Set the config to the right settings for a kafka test
    sig { void }
    def self.kafka_test!; end

    # Clear all sent messages - e.g. if we want to check that
    # particular messages were sent or not sent after a point in time.
    sig { void }
    def clear_kafka_messages!; end

    # Test that a given handler will consume a given payload correctly, i.e.
    # that the schema is correct. If
    # a block is given, that block will be executed when `consume` is called.
    # Otherwise it will just confirm that `consume` is called at all.
    # Deimos::Consumer or the topic as a string
    # to continue as normal. Not compatible with a block.
    # expectations on the consumer. Primarily used internally to Deimos.
    # 
    # _@param_ `handler_class_or_topic` — Class which inherits from
    # 
    # _@param_ `payload` — the payload to consume
    # 
    # _@param_ `call_original` — if true, allow the consume handler
    # 
    # _@param_ `skip_expectation` — Set to true to not place any
    # 
    # _@param_ `key` — the key to use.
    # 
    # _@param_ `partition_key` — the partition key to use.
    sig do
      params(
        handler_class_or_topic: T.any(T.class_of(BasicObject), String),
        payload: T::Hash[T.untyped, T.untyped],
        call_original: T::Boolean,
        key: T.nilable(Object),
        partition_key: T.nilable(Object),
        skip_expectation: T::Boolean,
        block: T.untyped
      ).void
    end
    def test_consume_message(handler_class_or_topic, payload, call_original: false, key: nil, partition_key: nil, skip_expectation: false, &block); end

    # Check to see that a given message will fail due to validation errors.
    # 
    # _@param_ `handler_class`
    # 
    # _@param_ `payload`
    sig { params(handler_class: T.class_of(BasicObject), payload: T::Hash[T.untyped, T.untyped]).void }
    def test_consume_invalid_message(handler_class, payload); end

    # Test that a given handler will consume a given batch payload correctly,
    # i.e. that the schema is correct. If
    # a block is given, that block will be executed when `consume` is called.
    # Otherwise it will just confirm that `consume` is called at all.
    # Deimos::Consumer or the topic as a string
    # 
    # _@param_ `handler_class_or_topic` — Class which inherits from
    # 
    # _@param_ `payloads` — the payload to consume
    # 
    # _@param_ `keys`
    # 
    # _@param_ `partition_keys`
    # 
    # _@param_ `call_original`
    # 
    # _@param_ `skip_expectation`
    sig do
      params(
        handler_class_or_topic: T.any(T.class_of(BasicObject), String),
        payloads: T::Array[T::Hash[T.untyped, T.untyped]],
        keys: T::Array[T.any(T::Hash[T.untyped, T.untyped], String)],
        partition_keys: T::Array[Integer],
        call_original: T::Boolean,
        skip_expectation: T::Boolean,
        block: T.untyped
      ).void
    end
    def test_consume_batch(handler_class_or_topic, payloads, keys: [], partition_keys: [], call_original: false, skip_expectation: false, &block); end

    # Check to see that a given message will fail due to validation errors.
    # 
    # _@param_ `handler_class`
    # 
    # _@param_ `payloads`
    sig { params(handler_class: T.class_of(BasicObject), payloads: T::Array[T::Hash[T.untyped, T.untyped]]).void }
    def test_consume_batch_invalid_message(handler_class, payloads); end
  end

  module Tracing
    # Class that mocks out tracing functionality
    class Mock < Deimos::Tracing::Provider
      # _@param_ `logger`
      sig { params(logger: T.nilable(Logger)).void }
      def initialize(logger = nil); end

      # _@param_ `span_name`
      # 
      # _@param_ `_options`
      sig { params(span_name: String, _options: T::Hash[T.untyped, T.untyped]).returns(Object) }
      def start(span_name, _options = {}); end

      # :nodoc:
      sig { params(span: Object).void }
      def finish(span); end

      # :nodoc:
      sig { returns(Object) }
      def active_span; end

      # :nodoc:
      sig { params(tag: String, value: String, span: T.nilable(Object)).void }
      def set_tag(tag, value, span = nil); end

      # :nodoc:
      sig { params(span: Object, exception: Exception).void }
      def set_error(span, exception); end
    end

    # Tracing wrapper class for Datadog.
    class Datadog < Deimos::Tracing::Provider
      # _@param_ `config`
      sig { params(config: T::Hash[T.untyped, T.untyped]).void }
      def initialize(config); end

      # :nodoc:
      sig { params(span_name: String, options: T::Hash[T.untyped, T.untyped]).returns(Object) }
      def start(span_name, options = {}); end

      # :nodoc:
      sig { params(span: Object).void }
      def finish(span); end

      # :nodoc:
      sig { returns(Object) }
      def active_span; end

      # :nodoc:
      sig { params(span: Object, exception: Exception).void }
      def set_error(span, exception); end

      # :nodoc:
      sig { params(tag: String, value: String, span: T.nilable(Object)).void }
      def set_tag(tag, value, span = nil); end
    end

    # Base class for all tracing providers.
    class Provider
      # Returns a span object and starts the trace.
      # 
      # _@param_ `span_name` — The name of the span/trace
      # 
      # _@param_ `options` — Options for the span
      # 
      # _@return_ — The span object
      sig { params(span_name: String, options: T::Hash[T.untyped, T.untyped]).returns(Object) }
      def start(span_name, options = {}); end

      # Finishes the trace on the span object.
      # 
      # _@param_ `span` — The span to finish trace on
      sig { params(span: Object).void }
      def finish(span); end

      # Set an error on the span.
      # 
      # _@param_ `span` — The span to set error on
      # 
      # _@param_ `exception` — The exception that occurred
      sig { params(span: Object, exception: Exception).void }
      def set_error(span, exception); end

      # Get the currently activated span.
      sig { returns(Object) }
      def active_span; end

      # Set a tag to a span. Use the currently active span if not given.
      # 
      # _@param_ `tag`
      # 
      # _@param_ `value`
      # 
      # _@param_ `span`
      sig { params(tag: String, value: String, span: T.nilable(Object)).void }
      def set_tag(tag, value, span = nil); end
    end
  end

  # Store Kafka messages into the database.
  class KafkaMessage < ActiveRecord::Base
    # Ensure it gets turned into a string, e.g. for testing purposes. It
    # should already be a string.
    # 
    # _@param_ `mess`
    sig { params(mess: Object).void }
    def message=(mess); end

    # Decoded payload for this message.
    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def decoded_message; end

    # Get a decoder to decode a set of messages on the given topic.
    # 
    # _@param_ `topic`
    sig { params(topic: String).returns(Deimos::Consumer) }
    def self.decoder(topic); end

    # Decoded payloads for a list of messages.
    # 
    # _@param_ `messages`
    sig { params(messages: T::Array[Deimos::KafkaMessage]).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def self.decoded(messages = []); end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def phobos_message; end
  end

  # Module that producers and consumers can share which sets up configuration.
  module SharedConfig
    extend ActiveSupport::Concern

    # need to use this instead of class_methods to be backwards-compatible
    # with Rails 3
    module ClassMethods
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def config; end

      # Set the schema.
      # 
      # _@param_ `schema`
      sig { params(schema: String).void }
      def schema(schema); end

      # Set the namespace.
      # 
      # _@param_ `namespace`
      sig { params(namespace: String).void }
      def namespace(namespace); end

      # Set key configuration.
      # 
      # _@param_ `field` — the name of a field to use in the value schema as a generated key schema
      # 
      # _@param_ `schema` — the name of a schema to use for the key
      # 
      # _@param_ `plain` — if true, do not encode keys at all
      # 
      # _@param_ `none` — if true, do not use keys at all
      sig do
        params(
          plain: T.nilable(T::Boolean),
          field: T.nilable(Symbol),
          schema: T.nilable(T.any(String, Symbol)),
          none: T.nilable(T::Boolean)
        ).void
      end
      def key_config(plain: nil, field: nil, schema: nil, none: nil); end

      # _@param_ `use_schema_classes`
      sig { params(use_schema_classes: T::Boolean).void }
      def schema_class_config(use_schema_classes); end
    end
  end

  # @deprecated Use Deimos::Consumer with `delivery: inline_batch` configured instead
  class BatchConsumer < Deimos::Consumer
  end

  # Copied from Phobos instrumentation.
  module Instrumentation
    extend ActiveSupport::Concern
    NAMESPACE = T.let('Deimos', T.untyped)

    # :nodoc:
    module ClassMethods
      # _@param_ `event`
      sig { params(event: String).void }
      def subscribe(event); end

      # _@param_ `subscriber`
      sig { params(subscriber: ActiveSupport::Subscriber).void }
      def unsubscribe(subscriber); end

      # _@param_ `event`
      # 
      # _@param_ `extra`
      sig { params(event: String, extra: T::Hash[T.untyped, T.untyped]).void }
      def instrument(event, extra = {}); end
    end
  end

  # This module listens to events published by RubyKafka.
  module KafkaListener
    # Listens for any exceptions that happen during publishing and re-publishes
    # as a Deimos event.
    # 
    # _@param_ `event`
    sig { params(event: ::ActiveSupport::Notifications::Event).void }
    def self.send_produce_error(event); end
  end

  module Utils
    # Class which continually polls the database and sends Kafka messages.
    module DbPoller
      # Begin the DB Poller process.
      sig { void }
      def self.start!; end

      # _@param_ `config_name`
      sig { params(config_name: FigTree::ConfigStruct).returns(T.class_of(Deimos::Utils::DbPoller)) }
      def self.class_for_config(config_name); end

      class PollStatus < Struct
        sig { returns(Integer) }
        def current_batch; end

        sig { returns(String) }
        def report; end

        # Returns the value of attribute batches_processed
        sig { returns(Object) }
        attr_accessor :batches_processed

        # Returns the value of attribute batches_errored
        sig { returns(Object) }
        attr_accessor :batches_errored

        # Returns the value of attribute messages_processed
        sig { returns(Object) }
        attr_accessor :messages_processed
      end

      # Base poller class for retrieving and publishing messages.
      class Base
        BATCH_SIZE = T.let(1000, T.untyped)

        # Method to define producers if a single poller needs to publish to multiple topics.
        # Producer classes should be constantized
        sig { returns(T::Array[Deimos::Producer]) }
        def self.producers; end

        # _@param_ `config`
        sig { params(config: FigTree::ConfigStruct).void }
        def initialize(config); end

        # Start the poll:
        # 1) Grab the current PollInfo from the database indicating the last
        # time we ran
        # 2) On a loop, process all the recent updates between the last time
        # we ran and now.
        sig { void }
        def start; end

        # Grab the PollInfo or create if it doesn't exist.
        sig { void }
        def retrieve_poll_info; end

        sig { returns(Deimos::PollInfo) }
        def create_poll_info; end

        # Indicate whether this current loop should process updates. Most loops
        # will busy-wait (sleeping 0.1 seconds) until it's ready.
        sig { returns(T::Boolean) }
        def should_run?; end

        # Stop the poll.
        sig { void }
        def stop; end

        # Send messages for updated data.
        sig { void }
        def process_updates; end

        # _@param_ `batch`
        # 
        # _@param_ `status`
        sig { params(batch: T::Array[ActiveRecord::Base], status: Deimos::Utils::DbPoller::PollStatus).returns(T::Boolean) }
        def process_batch_with_span(batch, status); end

        # Publish batch using the configured producers
        # 
        # _@param_ `batch`
        sig { params(batch: T::Array[ActiveRecord::Base]).void }
        def process_batch(batch); end

        # Configure log identifier and messages to be used in subclasses
        sig { returns(String) }
        def log_identifier; end

        # Return array of configured producers depending on poller class
        sig { returns(T::Array[Deimos::ActiveRecordProducer]) }
        def producer_classes; end

        # Validate if a producer class is an ActiveRecordProducer or not
        # 
        # _@param_ `producer_class`
        sig { params(producer_class: T.class_of(BasicObject)).void }
        def validate_producer_class(producer_class); end

        # Needed for Executor so it can identify the worker
        sig { returns(Integer) }
        attr_reader :id

        sig { returns(T::Hash[T.untyped, T.untyped]) }
        attr_reader :config
      end

      # Poller that uses ID and updated_at to determine the records to publish.
      class TimeBased < Deimos::Utils::DbPoller::Base
        BATCH_SIZE = T.let(1000, T.untyped)

        # :nodoc:
        sig { returns(Deimos::PollInfo) }
        def create_poll_info; end

        # _@param_ `batch`
        # 
        # _@param_ `status`
        sig { params(batch: T::Array[ActiveRecord::Base], status: Deimos::Utils::DbPoller::PollStatus).void }
        def process_and_touch_info(batch, status); end

        # Send messages for updated data.
        sig { void }
        def process_updates; end

        # _@param_ `time_from`
        # 
        # _@param_ `time_to`
        sig { params(time_from: ActiveSupport::TimeWithZone, time_to: ActiveSupport::TimeWithZone).returns(ActiveRecord::Relation) }
        def fetch_results(time_from, time_to); end

        # _@param_ `record`
        sig { params(record: ActiveRecord::Base).returns(ActiveSupport::TimeWithZone) }
        def last_updated(record); end

        # _@param_ `batch`
        sig { params(batch: T::Array[ActiveRecord::Base]).void }
        def touch_info(batch); end
      end

      # Poller that uses state columns to determine the records to publish.
      class StateBased < Deimos::Utils::DbPoller::Base
        BATCH_SIZE = T.let(1000, T.untyped)

        # Send messages for updated data.
        sig { void }
        def process_updates; end

        sig { returns(ActiveRecord::Relation) }
        def fetch_results; end

        # _@param_ `batch`
        # 
        # _@param_ `success`
        sig { params(batch: T::Array[ActiveRecord::Base], success: T::Boolean).void }
        def finalize_batch(batch, success); end
      end
    end

    # Class which continually polls the kafka_messages table
    # in the database and sends Kafka messages.
    class DbProducer
      include Phobos::Producer
      BATCH_SIZE = T.let(1000, T.untyped)
      DELETE_BATCH_SIZE = T.let(10, T.untyped)
      MAX_DELETE_ATTEMPTS = T.let(3, T.untyped)

      # _@param_ `logger`
      sig { params(logger: Logger).void }
      def initialize(logger = Logger.new(STDOUT)); end

      sig { returns(FigTree) }
      def config; end

      # Start the poll.
      sig { void }
      def start; end

      # Stop the poll.
      sig { void }
      def stop; end

      # Complete one loop of processing all messages in the DB.
      sig { void }
      def process_next_messages; end

      sig { returns(T::Array[String]) }
      def retrieve_topics; end

      # _@param_ `topic`
      # 
      # _@return_ — the topic that was locked, or nil if none were.
      sig { params(topic: String).returns(T.nilable(String)) }
      def process_topic(topic); end

      # Process a single batch in a topic.
      sig { void }
      def process_topic_batch; end

      # _@param_ `messages`
      sig { params(messages: T::Array[Deimos::KafkaMessage]).void }
      def delete_messages(messages); end

      sig { returns(T::Array[Deimos::KafkaMessage]) }
      def retrieve_messages; end

      # _@param_ `messages`
      sig { params(messages: T::Array[Deimos::KafkaMessage]).void }
      def log_messages(messages); end

      # Send metrics related to pending messages.
      sig { void }
      def send_pending_metrics; end

      # Shut down the sync producer if we have to. Phobos will automatically
      # create a new one. We should call this if the producer can be in a bad
      # state and e.g. we need to clear the buffer.
      sig { void }
      def shutdown_producer; end

      # Produce messages in batches, reducing the size 1/10 if the batch is too
      # large. Does not retry batches of messages that have already been sent.
      # 
      # _@param_ `batch`
      sig { params(batch: T::Array[T::Hash[T.untyped, T.untyped]]).void }
      def produce_messages(batch); end

      # _@param_ `batch`
      sig { params(batch: T::Array[Deimos::KafkaMessage]).returns(T::Array[Deimos::KafkaMessage]) }
      def compact_messages(batch); end

      # Returns the value of attribute id.
      sig { returns(T.untyped) }
      attr_accessor :id

      # Returns the value of attribute current_topic.
      sig { returns(T.untyped) }
      attr_accessor :current_topic
    end

    # Class that manages reporting lag.
    class LagReporter
      extend Mutex_m

      # Reset all group information.
      sig { void }
      def self.reset; end

      # offset_lag = event.payload.fetch(:offset_lag)
      # group_id = event.payload.fetch(:group_id)
      # topic = event.payload.fetch(:topic)
      # partition = event.payload.fetch(:partition)
      # 
      # _@param_ `payload`
      sig { params(payload: T::Hash[T.untyped, T.untyped]).void }
      def self.message_processed(payload); end

      # _@param_ `payload`
      sig { params(payload: T::Hash[T.untyped, T.untyped]).void }
      def self.offset_seek(payload); end

      # _@param_ `payload`
      sig { params(payload: T::Hash[T.untyped, T.untyped]).void }
      def self.heartbeat(payload); end

      # Class that has a list of topics
      class ConsumerGroup
        # _@param_ `id`
        sig { params(id: String).void }
        def initialize(id); end

        # _@param_ `topic`
        # 
        # _@param_ `partition`
        sig { params(topic: String, partition: Integer).void }
        def report_lag(topic, partition); end

        # _@param_ `topic`
        # 
        # _@param_ `partition`
        # 
        # _@param_ `offset`
        sig { params(topic: String, partition: Integer, offset: Integer).void }
        def assign_current_offset(topic, partition, offset); end

        sig { returns(T::Hash[String, Topic]) }
        attr_accessor :topics

        sig { returns(String) }
        attr_accessor :id
      end

      # Topic which has a hash of partition => last known current offsets
      class Topic
        # _@param_ `topic_name`
        # 
        # _@param_ `group`
        sig { params(topic_name: String, group: Deimos::Utils::LagReporter::ConsumerGroup).void }
        def initialize(topic_name, group); end

        # _@param_ `partition`
        # 
        # _@param_ `offset`
        sig { params(partition: Integer, offset: Integer).void }
        def assign_current_offset(partition, offset); end

        # _@param_ `partition`
        # 
        # _@param_ `offset`
        sig { params(partition: Integer, offset: Integer).returns(Integer) }
        def compute_lag(partition, offset); end

        # _@param_ `partition`
        sig { params(partition: Integer).void }
        def report_lag(partition); end

        sig { returns(String) }
        attr_accessor :topic_name

        sig { returns(T::Hash[Integer, Integer]) }
        attr_accessor :partition_current_offsets

        sig { returns(Deimos::Utils::LagReporter::ConsumerGroup) }
        attr_accessor :consumer_group
      end
    end

    # Class used by SchemaClassGenerator and Consumer/Producer interfaces
    module SchemaClass
      # _@param_ `namespace`
      sig { params(namespace: String).returns(T::Array[String]) }
      def self.modules_for(namespace); end

      # Converts a raw payload into an instance of the Schema Class
      # 
      # _@param_ `payload`
      # 
      # _@param_ `schema`
      # 
      # _@param_ `namespace`
      sig { params(payload: T.any(T::Hash[T.untyped, T.untyped], Deimos::SchemaClass::Base), schema: String, namespace: String).returns(Deimos::SchemaClass::Record) }
      def self.instance(payload, schema, namespace = ''); end

      # _@param_ `config` — Producer or Consumer config
      sig { params(config: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) }
      def self.use?(config); end
    end

    # Utility class to retry a given block if a a deadlock is encountered.
    # Supports Postgres and MySQL deadlocks and lock wait timeouts.
    class DeadlockRetry
      RETRY_COUNT = T.let(2, T.untyped)
      DEADLOCK_MESSAGES = T.let([
  # MySQL
  'Deadlock found when trying to get lock',
  'Lock wait timeout exceeded',

  # Postgres
  'deadlock detected'
].freeze, T.untyped)

      # Retry the given block when encountering a deadlock. For any other
      # exceptions, they are reraised. This is used to handle cases where
      # the database may be busy but the transaction would succeed if
      # retried later. Note that your block should be idempotent and it will
      # be wrapped in a transaction.
      # Sleeps for a random number of seconds to prevent multiple transactions
      # from retrying at the same time.
      # 
      # _@param_ `tags` — Tags to attach when logging and reporting metrics.
      sig { params(tags: T::Array[T.untyped]).void }
      def self.wrap(tags = []); end
    end

    # Listener that can seek to get the last X messages in a topic.
    class SeekListener < Phobos::Listener
      MAX_SEEK_RETRIES = T.let(3, T.untyped)

      sig { void }
      def start_listener; end

      sig { returns(Integer) }
      attr_accessor :num_messages
    end

    # Class to return the messages consumed.
    class MessageBankHandler < Deimos::Consumer
      include Phobos::Handler

      # _@param_ `klass`
      sig { params(klass: T.class_of(Deimos::Consumer)).void }
      def self.config_class=(klass); end

      # _@param_ `_kafka_client`
      sig { params(_kafka_client: Kafka::Client).void }
      def self.start(_kafka_client); end

      # _@param_ `payload`
      # 
      # _@param_ `metadata`
      sig { params(payload: T::Hash[T.untyped, T.untyped], metadata: T::Hash[T.untyped, T.untyped]).void }
      def consume(payload, metadata); end
    end

    # Class which can process/consume messages inline.
    class InlineConsumer
      MAX_MESSAGE_WAIT_TIME = T.let(1.second, T.untyped)
      MAX_TOPIC_WAIT_TIME = T.let(10.seconds, T.untyped)

      # Get the last X messages from a topic. You can specify a subclass of
      # Deimos::Consumer or Deimos::Producer, or provide the
      # schema, namespace and key_config directly.
      # 
      # _@param_ `topic`
      # 
      # _@param_ `config_class`
      # 
      # _@param_ `schema`
      # 
      # _@param_ `namespace`
      # 
      # _@param_ `key_config`
      # 
      # _@param_ `num_messages`
      sig do
        params(
          topic: String,
          schema: T.nilable(String),
          namespace: T.nilable(String),
          key_config: T.nilable(T::Hash[T.untyped, T.untyped]),
          config_class: T.nilable(T.any(T.class_of(Deimos::Consumer), T.class_of(Deimos::Producer))),
          num_messages: Integer
        ).returns(T::Array[T::Hash[T.untyped, T.untyped]])
      end
      def self.get_messages_for(topic:, schema: nil, namespace: nil, key_config: nil, config_class: nil, num_messages: 10); end

      # Consume the last X messages from a topic.
      # 
      # _@param_ `topic`
      # 
      # _@param_ `frk_consumer`
      # 
      # _@param_ `num_messages` — If this number is >= the number of messages in the topic, all messages will be consumed.
      sig { params(topic: String, frk_consumer: T.class_of(BasicObject), num_messages: Integer).void }
      def self.consume(topic:, frk_consumer:, num_messages: 10); end
    end

    # Mixin to automatically decode schema-encoded payloads when given the correct content type,
    # and provide the `render_schema` method to encode the payload for responses.
    module SchemaControllerMixin
      extend ActiveSupport::Concern

      sig { returns(T::Boolean) }
      def schema_format?; end

      # Get the namespace from either an existing instance variable, or tease it out of the schema.
      # 
      # _@param_ `type` — :request or :response
      # 
      # _@return_ — the namespace and schema.
      sig { params(type: Symbol).returns(T::Array[T.any(String, String)]) }
      def parse_namespace(type); end

      # Decode the payload with the parameters.
      sig { void }
      def decode_schema; end

      # Render a hash into a payload as specified by the configured schema and namespace.
      # 
      # _@param_ `payload`
      # 
      # _@param_ `schema`
      # 
      # _@param_ `namespace`
      sig { params(payload: T::Hash[T.untyped, T.untyped], schema: T.nilable(String), namespace: T.nilable(String)).void }
      def render_schema(payload, schema: nil, namespace: nil); end

      # :nodoc:
      module ClassMethods
        sig { returns(T::Hash[String, T::Hash[Symbol, String]]) }
        def schema_mapping; end

        # Indicate which schemas should be assigned to actions.
        # 
        # _@param_ `actions`
        # 
        # _@param_ `kwactions`
        # 
        # _@param_ `request`
        # 
        # _@param_ `response`
        sig do
          params(
            actions: Symbol,
            request: T.nilable(String),
            response: T.nilable(String),
            kwactions: String
          ).void
        end
        def schemas(*actions, request: nil, response: nil, **kwactions); end

        sig { returns(T::Hash[Symbol, String]) }
        def namespaces; end

        # Set the namespace for both requests and responses.
        # 
        # _@param_ `name`
        sig { params(name: String).void }
        def namespace(name); end

        # Set the namespace for requests.
        # 
        # _@param_ `name`
        sig { params(name: String).void }
        def request_namespace(name); end

        # Set the namespace for repsonses.
        # 
        # _@param_ `name`
        sig { params(name: String).void }
        def response_namespace(name); end
      end
    end
  end

  # Record that keeps track of which topics are being worked on by DbProducers.
  class KafkaTopicInfo < ActiveRecord::Base
    # Lock a topic for the given ID. Returns whether the lock was successful.
    # 
    # _@param_ `topic`
    # 
    # _@param_ `lock_id`
    sig { params(topic: String, lock_id: String).returns(T::Boolean) }
    def self.lock(topic, lock_id); end

    # This is called once a producer is finished working on a topic, i.e.
    # there are no more messages to fetch. It unlocks the topic and
    # moves on to the next one.
    # 
    # _@param_ `topic`
    # 
    # _@param_ `lock_id`
    sig { params(topic: String, lock_id: String).void }
    def self.clear_lock(topic, lock_id); end

    # Update all topics that aren't currently locked and have no messages
    # waiting. It's OK if some messages get inserted in the middle of this
    # because the point is that at least within a few milliseconds of each
    # other, it wasn't locked and had no messages, meaning the topic
    # was in a good state.
    # realized had messages in them, meaning all other topics were empty.
    # 
    # _@param_ `except_topics` — the list of topics we've just
    sig { params(except_topics: T::Array[String]).void }
    def self.ping_empty_topics(except_topics); end

    # The producer calls this if it gets an error sending messages. This
    # essentially locks down this topic for 1 minute (for all producers)
    # and allows the caller to continue to the next topic.
    # 
    # _@param_ `topic`
    # 
    # _@param_ `lock_id`
    sig { params(topic: String, lock_id: String).void }
    def self.register_error(topic, lock_id); end

    # Update the locked_at timestamp to indicate that the producer is still
    # working on those messages and to continue.
    # 
    # _@param_ `topic`
    # 
    # _@param_ `lock_id`
    sig { params(topic: String, lock_id: String).void }
    def self.heartbeat(topic, lock_id); end
  end

  module SchemaClass
    # Base Class for Schema Classes generated from Avro.
    class Base
      # _@param_ `_args`
      sig { params(_args: T::Array[Object]).void }
      def initialize(*_args); end

      # Converts the object to a hash which can be used for debugging or comparing objects.
      # 
      # _@param_ `_opts`
      # 
      # _@return_ — a hash representation of the payload
      sig { params(_opts: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
      def as_json(_opts = {}); end

      # _@param_ `key`
      # 
      # _@param_ `val`
      sig { params(key: T.any(String, Symbol), val: Object).void }
      def []=(key, val); end

      # _@param_ `other`
      sig { params(other: Deimos::SchemaClass::Base).returns(T::Boolean) }
      def ==(other); end

      sig { returns(String) }
      def inspect; end

      # Initializes this class from a given value
      # 
      # _@param_ `value`
      sig { params(value: Object).returns(Deimos::SchemaClass::Base) }
      def self.initialize_from_value(value); end

      sig { returns(Integer) }
      def hash; end
    end

    # Base Class for Enum Classes generated from Avro.
    class Enum < Deimos::SchemaClass::Base
      # _@param_ `other`
      sig { params(other: Deimos::SchemaClass::Enum).returns(T::Boolean) }
      def ==(other); end

      sig { returns(String) }
      def to_s; end

      # _@param_ `value`
      sig { params(value: String).void }
      def initialize(value); end

      # Returns all the valid symbols for this enum.
      sig { returns(T::Array[String]) }
      def symbols; end

      sig { params(_opts: T::Hash[T.untyped, T.untyped]).returns(String) }
      def as_json(_opts = {}); end

      sig { params(value: Object).returns(Deimos::SchemaClass::Enum) }
      def self.initialize_from_value(value); end

      sig { returns(String) }
      attr_accessor :value
    end

    # Base Class of Record Classes generated from Avro.
    class Record < Deimos::SchemaClass::Base
      # Converts the object attributes to a hash which can be used for Kafka
      # 
      # _@return_ — the payload as a hash.
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def to_h; end

      # Merge a hash or an identical schema object with this one and return a new object.
      # 
      # _@param_ `other_hash`
      sig { params(other_hash: T.any(T::Hash[T.untyped, T.untyped], Deimos::SchemaClass::Base)).returns(Deimos::SchemaClass::Base) }
      def merge(other_hash); end

      # Element access method as if this Object were a hash
      # 
      # _@param_ `key`
      # 
      # _@return_ — The value of the attribute if exists, nil otherwise
      sig { params(key: T.any(String, Symbol)).returns(Object) }
      def [](key); end

      sig { returns(Deimos::SchemaClass::Record) }
      def with_indifferent_access; end

      # Returns the schema name of the inheriting class.
      sig { returns(String) }
      def schema; end

      # Returns the namespace for the schema of the inheriting class.
      sig { returns(String) }
      def namespace; end

      # Returns the full schema name of the inheriting class.
      sig { returns(String) }
      def full_schema; end

      # Returns the schema validator from the schema backend
      sig { returns(Deimos::SchemaBackends::Base) }
      def validator; end

      # _@return_ — an array of fields names in the schema.
      sig { returns(T::Array[String]) }
      def schema_fields; end

      sig { params(value: Object).returns(Deimos::SchemaClass::Record) }
      def self.initialize_from_value(value); end

      # Returns the value of attribute tombstone_key.
      sig { returns(T.untyped) }
      attr_accessor :tombstone_key
    end
  end

  # Module to handle phobos.yml as well as outputting the configuration to save
  # to Phobos itself.
  module PhobosConfig
    extend ActiveSupport::Concern

    sig { void }
    def reset!; end

    # Create a hash representing the config that Phobos expects.
    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def phobos_config; end

    # _@param_ `key`
    sig { params(key: String).returns(String) }
    def ssl_var_contents(key); end
  end

  # Represents a field in the schema.
  class SchemaField
    # _@param_ `name`
    # 
    # _@param_ `type`
    # 
    # _@param_ `enum_values`
    # 
    # _@param_ `default`
    sig do
      params(
        name: String,
        type: Object,
        enum_values: T::Array[String],
        default: Object
      ).void
    end
    def initialize(name, type, enum_values = [], default = :no_default); end

    sig { returns(String) }
    attr_accessor :name

    sig { returns(String) }
    attr_accessor :type

    sig { returns(T::Array[String]) }
    attr_accessor :enum_values

    sig { returns(Object) }
    attr_accessor :default
  end

  module SchemaBackends
    # Base class for encoding / decoding.
    class Base
      # _@param_ `schema`
      # 
      # _@param_ `namespace`
      sig { params(schema: T.any(String, Symbol), namespace: T.nilable(String)).void }
      def initialize(schema:, namespace: nil); end

      # Encode a payload with a schema. Public method.
      # 
      # _@param_ `payload`
      # 
      # _@param_ `schema`
      # 
      # _@param_ `topic`
      sig { params(payload: T::Hash[T.untyped, T.untyped], schema: T.nilable(T.any(String, Symbol)), topic: T.nilable(String)).returns(String) }
      def encode(payload, schema: nil, topic: nil); end

      # Decode a payload with a schema. Public method.
      # 
      # _@param_ `payload`
      # 
      # _@param_ `schema`
      sig { params(payload: String, schema: T.nilable(T.any(String, Symbol))).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def decode(payload, schema: nil); end

      # Given a hash, coerce its types to our schema. To be defined by subclass.
      # 
      # _@param_ `payload`
      sig { params(payload: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
      def coerce(payload); end

      # Indicate a class which should act as a mocked version of this backend.
      # This class should perform all validations but not actually do any
      # encoding.
      # Note that the "mock" version (e.g. avro_validation) should return
      # its own symbol when this is called, since it may be called multiple
      # times depending on the order of RSpec helpers.
      sig { returns(Symbol) }
      def self.mock_backend; end

      # The content type to use when encoding / decoding requests over HTTP via ActionController.
      sig { returns(String) }
      def self.content_type; end

      # Converts your schema to String form for generated YARD docs.
      # To be defined by subclass.
      # 
      # _@param_ `schema`
      # 
      # _@return_ — A string representation of the Type
      sig { params(schema: Object).returns(String) }
      def self.field_type(schema); end

      # Encode a payload. To be defined by subclass.
      # 
      # _@param_ `payload`
      # 
      # _@param_ `schema`
      # 
      # _@param_ `topic`
      sig { params(payload: T::Hash[T.untyped, T.untyped], schema: T.any(String, Symbol), topic: T.nilable(String)).returns(String) }
      def encode_payload(payload, schema:, topic: nil); end

      # Decode a payload. To be defined by subclass.
      # 
      # _@param_ `payload`
      # 
      # _@param_ `schema`
      sig { params(payload: String, schema: T.any(String, Symbol)).returns(T::Hash[T.untyped, T.untyped]) }
      def decode_payload(payload, schema:); end

      # Validate that a payload matches the schema. To be defined by subclass.
      # 
      # _@param_ `payload`
      # 
      # _@param_ `schema`
      sig { params(payload: T::Hash[T.untyped, T.untyped], schema: T.any(String, Symbol)).void }
      def validate(payload, schema:); end

      # List of field names belonging to the schema. To be defined by subclass.
      sig { returns(T::Array[Deimos::SchemaField]) }
      def schema_fields; end

      # Given a value and a field definition (as defined by whatever the
      # underlying schema library is), coerce the given value to
      # the given field type.
      # 
      # _@param_ `field`
      # 
      # _@param_ `value`
      sig { params(field: Deimos::SchemaField, value: Object).returns(Object) }
      def coerce_field(field, value); end

      # Given a field definition, return the SQL type that might be used in
      # ActiveRecord table creation - e.g. for Avro, a `long` type would
      # return `:bigint`. There are also special values that need to be returned:
      # `:array`, `:map` and `:record`, for types representing those structures.
      # `:enum` is also recognized.
      # 
      # _@param_ `field`
      sig { params(field: Deimos::SchemaField).returns(Symbol) }
      def sql_type(field); end

      # Encode a message key. To be defined by subclass.
      # 
      # _@param_ `key` — the value to use as the key.
      # 
      # _@param_ `key_id` — the field name of the key.
      # 
      # _@param_ `topic`
      sig { params(key: T.any(String, T::Hash[T.untyped, T.untyped]), key_id: T.any(String, Symbol), topic: T.nilable(String)).returns(String) }
      def encode_key(key, key_id, topic: nil); end

      # Decode a message key. To be defined by subclass.
      # 
      # _@param_ `payload` — the message itself.
      # 
      # _@param_ `key_id` — the field in the message to decode.
      sig { params(payload: T::Hash[T.untyped, T.untyped], key_id: T.any(String, Symbol)).returns(String) }
      def decode_key(payload, key_id); end

      # Forcefully loads the schema into memory.
      # 
      # _@return_ — The schema that is of use.
      sig { returns(Object) }
      def load_schema; end

      sig { returns(String) }
      attr_accessor :schema

      sig { returns(String) }
      attr_accessor :namespace

      sig { returns(String) }
      attr_accessor :key_schema
    end

    # Mock implementation of a schema backend that does no encoding or validation.
    class Mock < Deimos::SchemaBackends::Base
      sig { params(payload: String, schema: T.any(String, Symbol)).returns(T::Hash[T.untyped, T.untyped]) }
      def decode_payload(payload, schema:); end

      sig { params(payload: T::Hash[T.untyped, T.untyped], schema: T.any(String, Symbol), topic: T.nilable(String)).returns(String) }
      def encode_payload(payload, schema:, topic: nil); end

      sig { params(payload: T::Hash[T.untyped, T.untyped], schema: T.any(String, Symbol)).void }
      def validate(payload, schema:); end

      sig { returns(T::Array[Deimos::SchemaField]) }
      def schema_fields; end

      # _@param_ `_field`
      # 
      # _@param_ `value`
      sig { params(_field: Deimos::SchemaField, value: Object).returns(Object) }
      def coerce_field(_field, value); end

      sig { params(key_id: T.any(String, Symbol), key: T.any(String, T::Hash[T.untyped, T.untyped]), topic: T.nilable(String)).returns(String) }
      def encode_key(key_id, key, topic: nil); end

      sig { params(payload: T::Hash[T.untyped, T.untyped], key_id: T.any(String, Symbol)).returns(String) }
      def decode_key(payload, key_id); end
    end

    # Encode / decode using Avro, either locally or via schema registry.
    class AvroBase < Deimos::SchemaBackends::Base
      sig { params(schema: T.any(String, Symbol), namespace: String).void }
      def initialize(schema:, namespace:); end

      sig { params(key_id: T.any(String, Symbol), key: T.any(String, T::Hash[T.untyped, T.untyped]), topic: T.nilable(String)).returns(String) }
      def encode_key(key_id, key, topic: nil); end

      sig { params(payload: T::Hash[T.untyped, T.untyped], key_id: T.any(String, Symbol)).returns(String) }
      def decode_key(payload, key_id); end

      # :nodoc:
      sig { params(field: Deimos::SchemaField).returns(Symbol) }
      def sql_type(field); end

      sig { params(field: Deimos::SchemaField, value: Object).returns(Object) }
      def coerce_field(field, value); end

      sig { returns(T::Array[Deimos::SchemaField]) }
      def schema_fields; end

      sig { params(payload: T::Hash[T.untyped, T.untyped], schema: T.any(String, Symbol)).void }
      def validate(payload, schema:); end

      sig { returns(Avro::Schema) }
      def load_schema; end

      sig { returns(Symbol) }
      def self.mock_backend; end

      sig { returns(String) }
      def self.content_type; end

      # _@param_ `schema` — A named schema
      sig { params(schema: Avro::Schema::NamedSchema).returns(String) }
      def self.schema_classname(schema); end

      # Converts Avro::Schema::NamedSchema's to String form for generated YARD docs.
      # Recursively handles the typing for Arrays, Maps and Unions.
      # 
      # _@param_ `avro_schema`
      # 
      # _@return_ — A string representation of the Type of this SchemaField
      sig { params(avro_schema: Avro::Schema::NamedSchema).returns(String) }
      def self.field_type(avro_schema); end

      # Returns the base type of this schema. Decodes Arrays, Maps and Unions
      # 
      # _@param_ `schema`
      sig { params(schema: Avro::Schema::NamedSchema).returns(Avro::Schema::NamedSchema) }
      def self.schema_base_class(schema); end

      # Returns the value of attribute schema_store.
      sig { returns(T.untyped) }
      attr_accessor :schema_store
    end

    # Encode / decode using local Avro encoding.
    class AvroLocal < Deimos::SchemaBackends::AvroBase
      sig { params(payload: String, schema: T.any(String, Symbol)).returns(T::Hash[T.untyped, T.untyped]) }
      def decode_payload(payload, schema:); end

      sig { params(payload: T::Hash[T.untyped, T.untyped], schema: T.nilable(T.any(String, Symbol)), topic: T.nilable(String)).returns(String) }
      def encode_payload(payload, schema: nil, topic: nil); end
    end

    # Leave Ruby hashes as is but validate them against the schema.
    # Useful for unit tests.
    class AvroValidation < Deimos::SchemaBackends::AvroBase
      sig { params(payload: String, schema: T.nilable(T.any(String, Symbol))).returns(T::Hash[T.untyped, T.untyped]) }
      def decode_payload(payload, schema: nil); end

      sig { params(payload: T::Hash[T.untyped, T.untyped], schema: T.nilable(T.any(String, Symbol)), topic: T.nilable(String)).returns(String) }
      def encode_payload(payload, schema: nil, topic: nil); end
    end

    # Encode / decode using the Avro schema registry.
    class AvroSchemaRegistry < Deimos::SchemaBackends::AvroBase
      sig { params(payload: String, schema: T.any(String, Symbol)).returns(T::Hash[T.untyped, T.untyped]) }
      def decode_payload(payload, schema:); end

      sig { params(payload: T::Hash[T.untyped, T.untyped], schema: T.nilable(T.any(String, Symbol)), topic: T.nilable(String)).returns(String) }
      def encode_payload(payload, schema: nil, topic: nil); end
    end
  end

  # To configure batch vs. message mode, change the delivery mode of your
  # Phobos listener.
  # Message-by-message -> use `delivery: message` or `delivery: batch`
  # Batch -> use `delivery: inline_batch`
  class ActiveRecordConsumer < Deimos::Consumer
    include Deimos::ActiveRecordConsume::MessageConsumption
    include Deimos::ActiveRecordConsume::BatchConsumption

    # database.
    # 
    # _@param_ `klass` — the class used to save to the
    sig { params(klass: T.class_of(ActiveRecord::Base)).void }
    def self.record_class(klass); end

    sig { returns(T.nilable(String)) }
    def self.bulk_import_id_column; end

    # only the last message for each unique key in a batch is processed.
    # 
    # _@param_ `val` — Turn pre-compaction of the batch on or off. If true,
    sig { params(val: T::Boolean).void }
    def self.compacted(val); end

    # _@param_ `limit` — Maximum number of transactions in a single database call.
    sig { params(limit: Integer).void }
    def self.max_db_batch_size(limit); end

    # Setup
    sig { void }
    def initialize; end

    # Override this method (with `super`) if you want to add/change the default
    # attributes set to the new/existing record.
    # 
    # _@param_ `payload`
    # 
    # _@param_ `_key`
    sig { params(payload: T.any(T::Hash[T.untyped, T.untyped], Deimos::SchemaClass::Record), _key: T.nilable(String)).returns(T::Hash[T.untyped, T.untyped]) }
    def record_attributes(payload, _key = nil); end

    # Override this message to conditionally save records
    # 
    # _@param_ `_payload` — The kafka message
    # 
    # _@return_ — if true, record is created/update.
    # If false, record processing is skipped but message offset is still committed.
    sig { params(_payload: T.any(T::Hash[T.untyped, T.untyped], Deimos::SchemaClass::Record)).returns(T::Boolean) }
    def process_message?(_payload); end

    # Handle a batch of Kafka messages. Batches are split into "slices",
    # which are groups of independent messages that can be processed together
    # in a single database operation.
    # If two messages in a batch have the same key, we cannot process them
    # in the same operation as they would interfere with each other. Thus
    # they are split
    # 
    # _@param_ `payloads` — Decoded payloads
    # 
    # _@param_ `metadata` — Information about batch, including keys.
    sig { params(payloads: T::Array[T.any(T::Hash[T.untyped, T.untyped], Deimos::SchemaClass::Record)], metadata: T::Hash[T.untyped, T.untyped]).void }
    def consume_batch(payloads, metadata); end

    # Get the set of attribute names that uniquely identify messages in the
    # batch. Requires at least one record.
    # The parameters are mutually exclusive. records is used by default implementation.
    # 
    # _@param_ `_klass` — Class Name can be used to fetch columns
    # 
    # _@return_ — List of attribute names.
    sig { params(_klass: T.class_of(ActiveRecord::Base)).returns(T.nilable(T::Array[String])) }
    def key_columns(_klass); end

    # Get the list of database table column names that should be saved to the database
    # 
    # _@param_ `_klass` — ActiveRecord class associated to the Entity Object
    # 
    # _@return_ — list of table columns
    sig { params(_klass: T.class_of(ActiveRecord::Base)).returns(T.nilable(T::Array[String])) }
    def columns(_klass); end

    # Get unique key for the ActiveRecord instance from the incoming key.
    # Override this method (with super) to customize the set of attributes that
    # uniquely identifies each record in the database.
    # 
    # _@param_ `key` — The encoded key.
    # 
    # _@return_ — The key attributes.
    sig { params(key: T.any(String, T::Hash[T.untyped, T.untyped])).returns(T::Hash[T.untyped, T.untyped]) }
    def record_key(key); end

    # Create an ActiveRecord relation that matches all of the passed
    # records. Used for bulk deletion.
    # 
    # _@param_ `records` — List of messages.
    # 
    # _@return_ — Matching relation.
    sig { params(records: T::Array[Deimos::Message]).returns(ActiveRecord::Relation) }
    def deleted_query(records); end

    # _@param_ `_record`
    sig { params(_record: ActiveRecord::Base).returns(T::Boolean) }
    def should_consume?(_record); end

    # Find the record specified by the given payload and key.
    # Default is to use the primary key column and the value of the first
    # field in the key.
    # 
    # _@param_ `klass`
    # 
    # _@param_ `_payload`
    # 
    # _@param_ `key`
    sig { params(klass: T.class_of(ActiveRecord::Base), _payload: T.any(T::Hash[T.untyped, T.untyped], Deimos::SchemaClass::Record), key: Object).returns(ActiveRecord::Base) }
    def fetch_record(klass, _payload, key); end

    # Assign a key to a new record.
    # 
    # _@param_ `record`
    # 
    # _@param_ `_payload`
    # 
    # _@param_ `key`
    sig { params(record: ActiveRecord::Base, _payload: T.any(T::Hash[T.untyped, T.untyped], Deimos::SchemaClass::Record), key: Object).void }
    def assign_key(record, _payload, key); end

    # _@param_ `payload` — Decoded payloads
    # 
    # _@param_ `metadata` — Information about batch, including keys.
    sig { params(payload: T.any(T::Hash[T.untyped, T.untyped], Deimos::SchemaClass::Record), metadata: T::Hash[T.untyped, T.untyped]).void }
    def consume(payload, metadata); end

    # _@param_ `record`
    sig { params(record: ActiveRecord::Base).void }
    def save_record(record); end

    # Destroy a record that received a null payload. Override if you need
    # to do something other than a straight destroy (e.g. mark as archived).
    # 
    # _@param_ `record`
    sig { params(record: ActiveRecord::Base).void }
    def destroy_record(record); end
  end

  # Class which automatically produces a record when given an ActiveRecord
  # instance or a list of them. Just call `send_events` on a list of records
  # and they will be auto-published. You can override `generate_payload`
  # to make changes to the payload before it's published.
  # 
  # You can also call this with a list of hashes representing attributes.
  # This is common when using activerecord-import.
  class ActiveRecordProducer < Deimos::Producer
    MAX_BATCH_SIZE = T.let(500, T.untyped)

    # Indicate the class this producer is working on.
    # a record object, refetch the record to pass into the `generate_payload`
    # method.
    # 
    # _@param_ `klass`
    # 
    # _@param_ `refetch` — if true, and we are given a hash instead of
    sig { params(klass: T.class_of(BasicObject), refetch: T::Boolean).void }
    def self.record_class(klass, refetch: true); end

    # _@param_ `record`
    # 
    # _@param_ `force_send`
    sig { params(record: ActiveRecord::Base, force_send: T::Boolean).void }
    def self.send_event(record, force_send: false); end

    # _@param_ `records`
    # 
    # _@param_ `force_send`
    sig { params(records: T::Array[ActiveRecord::Base], force_send: T::Boolean).void }
    def self.send_events(records, force_send: false); end

    # Generate the payload, given a list of attributes or a record..
    # Can be overridden or added to by subclasses.
    # is not set.
    # 
    # _@param_ `attributes`
    # 
    # _@param_ `_record` — May be nil if refetch_record
    sig { params(attributes: T::Hash[T.untyped, T.untyped], _record: ActiveRecord::Base).returns(T::Hash[T.untyped, T.untyped]) }
    def self.generate_payload(attributes, _record); end

    # Query to use when polling the database with the DbPoller. Add
    # includes, joins, or wheres as necessary, or replace entirely.
    # than this value).
    # 
    # _@param_ `time_from` — the time to start the query from.
    # 
    # _@param_ `time_to` — the time to end the query.
    # 
    # _@param_ `column_name` — the column name to look for.
    # 
    # _@param_ `min_id` — the minimum ID (i.e. all IDs must be greater
    sig do
      params(
        time_from: Time,
        time_to: Time,
        min_id: Numeric,
        column_name: Symbol
      ).returns(ActiveRecord::Relation)
    end
    def self.poll_query(time_from:, time_to:, min_id:, column_name: :updated_at); end

    # Post process records after publishing
    # 
    # _@param_ `_records`
    sig { params(_records: T::Array[ActiveRecord::Base]).void }
    def self.post_process(_records); end
  end

  module Consume
    # Helper methods used by batch consumers, i.e. those with "inline_batch"
    # delivery. Payloads are decoded then consumers are invoked with arrays
    # of messages to be handled at once
    module BatchConsumption
      include Phobos::BatchHandler
      extend ActiveSupport::Concern

      # _@param_ `batch`
      # 
      # _@param_ `metadata`
      sig { params(batch: T::Array[String], metadata: T::Hash[T.untyped, T.untyped]).void }
      def around_consume_batch(batch, metadata); end

      # Consume a batch of incoming messages.
      # 
      # _@param_ `_payloads`
      # 
      # _@param_ `_metadata`
      sig { params(_payloads: T::Array[Phobos::BatchMessage], _metadata: T::Hash[T.untyped, T.untyped]).void }
      def consume_batch(_payloads, _metadata); end
    end

    # Methods used by message-by-message (non-batch) consumers. These consumers
    # are invoked for every individual message.
    module MessageConsumption
      include Phobos::Handler
      extend ActiveSupport::Concern

      # _@param_ `payload`
      # 
      # _@param_ `metadata`
      sig { params(payload: String, metadata: T::Hash[T.untyped, T.untyped]).void }
      def around_consume(payload, metadata); end

      # Consume incoming messages.
      # 
      # _@param_ `_payload`
      # 
      # _@param_ `_metadata`
      sig { params(_payload: String, _metadata: T::Hash[T.untyped, T.untyped]).void }
      def consume(_payload, _metadata); end
    end
  end

  module Generators
    # Generate the database backend migration.
    class DbPollerGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      include ActiveRecord::Generators::Migration
      extend ActiveRecord::Generators::Migration

      sig { returns(String) }
      def migration_version; end

      sig { returns(String) }
      def db_migrate_path; end

      # Main method to create all the necessary files
      sig { void }
      def generate; end
    end

    # Generate the database backend migration.
    class DbBackendGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      include ActiveRecord::Generators::Migration
      extend ActiveRecord::Generators::Migration

      sig { returns(String) }
      def migration_version; end

      sig { returns(String) }
      def db_migrate_path; end

      # Main method to create all the necessary files
      sig { void }
      def generate; end
    end

    # Generator for Schema Classes used for the IDE and consumer/producer interfaces
    class SchemaClassGenerator < Rails::Generators::Base
      SPECIAL_TYPES = T.let(%i(record enum).freeze, T.untyped)
      INITIALIZE_WHITESPACE = T.let("\n#{' ' * 19}", T.untyped)
      IGNORE_DEFAULTS = T.let(%w(message_id timestamp).freeze, T.untyped)
      SCHEMA_CLASS_FILE = T.let('schema_class.rb', T.untyped)
      SCHEMA_RECORD_PATH = T.let(File.expand_path('schema_class/templates/schema_record.rb.tt', __dir__).freeze, T.untyped)
      SCHEMA_ENUM_PATH = T.let(File.expand_path('schema_class/templates/schema_enum.rb.tt', __dir__).freeze, T.untyped)

      sig { void }
      def generate; end
    end

    # Generator for ActiveRecord model and migration.
    class ActiveRecordGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      include ActiveRecord::Generators::Migration
      extend ActiveRecord::Generators::Migration

      sig { void }
      def generate; end
    end

    # Generator for ActiveRecord model and migration.
    class BulkImportIdGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      include ActiveRecord::Generators::Migration

      # For a given table_name and column_name, create a migration to add the column
      # column_name defaults to bulk_import_id
      sig { void }
      def generate; end
    end
  end

  module ActiveRecordConsume
    # Keeps track of both an ActiveRecord instance and more detailed attributes.
    # The attributes are needed for nested associations.
    class BatchRecord
      # _@param_ `klass`
      # 
      # _@param_ `attributes` — the full attribute list, including associations.
      # 
      # _@param_ `bulk_import_column`
      sig { params(klass: T.class_of(ActiveRecord::Base), attributes: T::Hash[T.untyped, T.untyped], bulk_import_column: T.nilable(String)).void }
      def initialize(klass:, attributes:, bulk_import_column: nil); end

      # Checks whether the entities has necessary columns for association saving to work
      # 
      # _@return_ — void
      sig { returns(T.untyped) }
      def validate_import_id!; end

      sig { returns(T.class_of(ActiveRecord::Base)) }
      def klass; end

      # Create a list of BatchRecord instances representing associated objects for the given
      # association name.
      # parent bulk_insert_id, where each record has a unique UUID,
      # this is used to detect and delete old data, so this is basically a "session ID" for this
      # bulk upsert.
      # 
      # _@param_ `assoc_name`
      # 
      # _@param_ `bulk_import_id` — A UUID which should be set on *every* sub-record. Unlike the
      sig { params(assoc_name: String, bulk_import_id: T.nilable(String)).returns(T::Array[Deimos::ActiveRecordConsume::BatchRecord]) }
      def sub_records(assoc_name, bulk_import_id = nil); end

      sig { returns(ActiveRecord::Base) }
      attr_accessor :record

      # For has_one, the format would be e.g. { 'detail' => { 'foo' => 'bar'}}. For has_many, it would
      # be an array, e.g. { 'details' => [{'foo' => 'bar'}, {'foo' => 'baz'}]}
      # 
      # _@return_ — a set of association information, represented by a hash of attributes.
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      attr_accessor :associations

      # the in-memory record.
      # 
      # _@return_ — A unique UUID used to associate the auto-increment ID back to
      sig { returns(String) }
      attr_accessor :bulk_import_id

      # _@return_ — The column name to use for bulk IDs - defaults to `bulk_import_id`.
      sig { returns(String) }
      attr_accessor :bulk_import_column
    end

    # Helper class for breaking down batches into independent groups for
    # processing
    class BatchSlicer
      # Split the batch into a series of independent slices. Each slice contains
      # messages that can be processed in any order (i.e. they have distinct
      # keys). Messages with the same key will be separated into different
      # slices that maintain the correct order.
      # E.g. Given messages A1, A2, B1, C1, C2, C3, they will be sliced as:
      # [[A1, B1, C1], [A2, C2], [C3]]
      # 
      # _@param_ `messages`
      sig { params(messages: T::Array[Deimos::Message]).returns(T::Array[T::Array[Deimos::Message]]) }
      def self.slice(messages); end
    end

    # Responsible for updating the database itself.
    class MassUpdater
      # _@param_ `klass`
      sig { params(klass: T.class_of(ActiveRecord::Base)).returns(T::Array[String]) }
      def default_keys(klass); end

      # _@param_ `klass`
      sig { params(klass: T.class_of(ActiveRecord::Base)).returns(String) }
      def default_cols(klass); end

      # _@param_ `klass`
      # 
      # _@param_ `key_col_proc`
      # 
      # _@param_ `col_proc`
      # 
      # _@param_ `replace_associations`
      sig do
        params(
          klass: T.class_of(ActiveRecord::Base),
          key_col_proc: T.nilable(Proc),
          col_proc: T.nilable(Proc),
          replace_associations: T::Boolean
        ).void
      end
      def initialize(klass, key_col_proc: nil, col_proc: nil, replace_associations: true); end

      # _@param_ `klass`
      sig { params(klass: T.class_of(ActiveRecord::Base)).returns(T::Array[String]) }
      def columns(klass); end

      # _@param_ `klass`
      sig { params(klass: T.class_of(ActiveRecord::Base)).returns(T::Array[String]) }
      def key_cols(klass); end

      # _@param_ `record_list`
      sig { params(record_list: Deimos::ActiveRecordConsume::BatchRecordList).void }
      def save_records_to_database(record_list); end

      # Imports associated objects and import them to database table
      # The base table is expected to contain bulk_import_id column for indexing associated objects with id
      # 
      # _@param_ `record_list`
      sig { params(record_list: Deimos::ActiveRecordConsume::BatchRecordList).void }
      def import_associations(record_list); end

      # _@param_ `record_list`
      sig { params(record_list: Deimos::ActiveRecordConsume::BatchRecordList).void }
      def mass_update(record_list); end
    end

    # Methods for consuming batches of messages and saving them to the database
    # in bulk ActiveRecord operations.
    module BatchConsumption
      # Handle a batch of Kafka messages. Batches are split into "slices",
      # which are groups of independent messages that can be processed together
      # in a single database operation.
      # If two messages in a batch have the same key, we cannot process them
      # in the same operation as they would interfere with each other. Thus
      # they are split
      # 
      # _@param_ `payloads` — Decoded payloads
      # 
      # _@param_ `metadata` — Information about batch, including keys.
      sig { params(payloads: T::Array[T.any(T::Hash[T.untyped, T.untyped], Deimos::SchemaClass::Record)], metadata: T::Hash[T.untyped, T.untyped]).void }
      def consume_batch(payloads, metadata); end

      # Get the set of attribute names that uniquely identify messages in the
      # batch. Requires at least one record.
      # The parameters are mutually exclusive. records is used by default implementation.
      # 
      # _@param_ `_klass` — Class Name can be used to fetch columns
      # 
      # _@return_ — List of attribute names.
      sig { params(_klass: T.class_of(ActiveRecord::Base)).returns(T.nilable(T::Array[String])) }
      def key_columns(_klass); end

      # Get the list of database table column names that should be saved to the database
      # 
      # _@param_ `_klass` — ActiveRecord class associated to the Entity Object
      # 
      # _@return_ — list of table columns
      sig { params(_klass: T.class_of(ActiveRecord::Base)).returns(T.nilable(T::Array[String])) }
      def columns(_klass); end

      # Get unique key for the ActiveRecord instance from the incoming key.
      # Override this method (with super) to customize the set of attributes that
      # uniquely identifies each record in the database.
      # 
      # _@param_ `key` — The encoded key.
      # 
      # _@return_ — The key attributes.
      sig { params(key: T.any(String, T::Hash[T.untyped, T.untyped])).returns(T::Hash[T.untyped, T.untyped]) }
      def record_key(key); end

      # Create an ActiveRecord relation that matches all of the passed
      # records. Used for bulk deletion.
      # 
      # _@param_ `records` — List of messages.
      # 
      # _@return_ — Matching relation.
      sig { params(records: T::Array[Deimos::Message]).returns(ActiveRecord::Relation) }
      def deleted_query(records); end

      # _@param_ `_record`
      sig { params(_record: ActiveRecord::Base).returns(T::Boolean) }
      def should_consume?(_record); end
    end

    # A set of BatchRecords which typically are worked with together (hence the batching!)
    class BatchRecordList
      # _@param_ `records`
      sig { params(records: T::Array[Deimos::ActiveRecordConsume::BatchRecord]).void }
      def initialize(records); end

      # Filter out any invalid records.
      # 
      # _@param_ `method`
      sig { params(method: Proc).void }
      def filter!(method); end

      # Get the original ActiveRecord objects.
      sig { returns(T::Array[ActiveRecord::Base]) }
      def records; end

      # Get the list of relevant associations, based on the keys of the association hashes of all
      # records in this list.
      sig { returns(T::Array[ActiveRecord::Reflection::AssociationReflection]) }
      def associations; end

      # Go back to the DB and use the bulk_import_id to set the actual primary key (`id`) of the
      # records.
      sig { void }
      def fill_primary_keys!; end

      # _@param_ `assoc_name`
      sig { params(assoc_name: String).returns(T::Array[T.any(Integer, String)]) }
      def primary_keys(assoc_name); end

      # _@param_ `assoc`
      # 
      # _@param_ `import_id`
      sig { params(assoc: ActiveRecord::Reflection::AssociationReflection, import_id: String).void }
      def delete_old_records(assoc, import_id); end

      sig { returns(T::Array[Deimos::ActiveRecordConsume::BatchRecord]) }
      attr_accessor :batch_records

      sig { returns(T.class_of(BasicObject)) }
      attr_accessor :klass

      sig { returns(String) }
      attr_accessor :bulk_import_column
    end

    # Methods for consuming individual messages and saving them to the database
    # as ActiveRecord instances.
    module MessageConsumption
      # Find the record specified by the given payload and key.
      # Default is to use the primary key column and the value of the first
      # field in the key.
      # 
      # _@param_ `klass`
      # 
      # _@param_ `_payload`
      # 
      # _@param_ `key`
      sig { params(klass: T.class_of(ActiveRecord::Base), _payload: T.any(T::Hash[T.untyped, T.untyped], Deimos::SchemaClass::Record), key: Object).returns(ActiveRecord::Base) }
      def fetch_record(klass, _payload, key); end

      # Assign a key to a new record.
      # 
      # _@param_ `record`
      # 
      # _@param_ `_payload`
      # 
      # _@param_ `key`
      sig { params(record: ActiveRecord::Base, _payload: T.any(T::Hash[T.untyped, T.untyped], Deimos::SchemaClass::Record), key: Object).void }
      def assign_key(record, _payload, key); end

      # _@param_ `payload` — Decoded payloads
      # 
      # _@param_ `metadata` — Information about batch, including keys.
      sig { params(payload: T.any(T::Hash[T.untyped, T.untyped], Deimos::SchemaClass::Record), metadata: T::Hash[T.untyped, T.untyped]).void }
      def consume(payload, metadata); end

      # _@param_ `record`
      sig { params(record: ActiveRecord::Base).void }
      def save_record(record); end

      # Destroy a record that received a null payload. Override if you need
      # to do something other than a straight destroy (e.g. mark as archived).
      # 
      # _@param_ `record`
      sig { params(record: ActiveRecord::Base).void }
      def destroy_record(record); end
    end

    # Convert a message with a schema to an ActiveRecord model
    class SchemaModelConverter
      # Create new converter
      # 
      # _@param_ `decoder` — Incoming message schema.
      # 
      # _@param_ `klass` — Model to map to.
      sig { params(decoder: Deimos::SchemaBackends::Base, klass: ActiveRecord::Base).void }
      def initialize(decoder, klass); end

      # Convert a message from a decoded hash to a set of ActiveRecord
      # attributes. Attributes that don't exist in the model will be ignored.
      # 
      # _@param_ `payload` — Decoded message payload.
      # 
      # _@return_ — Model attributes.
      sig { params(payload: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
      def convert(payload); end
    end
  end

  # Class to coerce values in a payload to match a schema.
  class AvroSchemaCoercer
    # _@param_ `schema`
    sig { params(schema: Avro::Schema).void }
    def initialize(schema); end

    # Coerce sub-records in a payload to match the schema.
    # 
    # _@param_ `type`
    # 
    # _@param_ `val`
    sig { params(type: Avro::Schema::UnionSchema, val: Object).returns(Object) }
    def coerce_union(type, val); end

    # Coerce sub-records in a payload to match the schema.
    # 
    # _@param_ `type`
    # 
    # _@param_ `val`
    sig { params(type: Avro::Schema::RecordSchema, val: Object).returns(Object) }
    def coerce_record(type, val); end

    # Coerce values in a payload to match the schema.
    # 
    # _@param_ `type`
    # 
    # _@param_ `val`
    sig { params(type: Avro::Schema, val: Object).returns(Object) }
    def coerce_type(type, val); end
  end
end
