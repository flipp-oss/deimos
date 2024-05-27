# frozen_string_literal: true

require 'active_support'
require 'karafka'

require 'deimos/version'
require 'deimos/logging'
require 'deimos/config/configuration'
require 'deimos/producer'
require 'deimos/active_record_producer'
require 'deimos/active_record_consumer'
require 'deimos/consumer'

require 'deimos/backends/base'
require 'deimos/backends/kafka'
require 'deimos/backends/kafka_async'
require 'deimos/backends/test'

require 'deimos/schema_backends/base'
require 'deimos/utils/schema_class'
require 'deimos/schema_class/enum'
require 'deimos/schema_class/record'

require 'deimos/ext/schema_route'
require 'deimos/ext/consumer_route'
require 'deimos/ext/producer_route'
require 'deimos/ext/producer_middleware'

require 'deimos/railtie' if defined?(Rails)
require 'deimos/utils/schema_controller_mixin' if defined?(ActionController)

if defined?(ActiveRecord)
  require 'deimos/kafka_source'
  require 'deimos/kafka_topic_info'
  require 'deimos/backends/outbox'
  require 'sigurd'
  require 'deimos/utils/outbox_producer'
  require 'deimos/utils/db_poller'
end

require 'yaml'
require 'erb'

# Parent module.
module Deimos
  class << self
    # @return [Class<Deimos::SchemaBackends::Base>]
    def schema_backend_class
      backend = Deimos.config.schema.backend.to_s

      require "deimos/schema_backends/#{backend}"

      "Deimos::SchemaBackends::#{backend.classify}".constantize
    end

    # @param schema [String, Symbol]
    # @param namespace [String]
    # @return [Deimos::SchemaBackends::Base]
    def schema_backend(schema:, namespace:)
      if config.schema.use_schema_classes
        # Initialize an instance of the provided schema
        # in the event the schema class is an override, the inherited
        # schema and namespace will be applied
        schema_class = Utils::SchemaClass.klass(schema, namespace)
        if schema_class.nil?
          schema_backend_class.new(schema: schema, namespace: namespace)
        else
          schema_instance = schema_class.new
          schema_backend_class.new(schema: schema_instance.schema, namespace: schema_instance.namespace)
        end
      else
        schema_backend_class.new(schema: schema, namespace: namespace)
      end
    end

    # @param schema [String]
    # @param namespace [String]
    # @param payload [Hash]
    # @param subject [String]
    # @return [String]
    def encode(schema:, namespace:, payload:, subject: nil)
      self.schema_backend(schema: schema, namespace: namespace).
        encode(payload, topic: subject || "#{namespace}.#{schema}" )
    end

    # @param schema [String]
    # @param namespace [String]
    # @param payload [String]
    # @return [Hash,nil]
    def decode(schema:, namespace:, payload:)
      self.schema_backend(schema: schema, namespace: namespace).decode(payload)
    end

    # @param message [Hash] a Karafka message with keys :payload, :key and :topic
    def decode_message(message)
      topic = message[:topic]
      if Deimos.config.producers.topic_prefix
        topic = topic.sub(Deimos.config.producers.topic_prefix, '')
      end
      config = karafka_config_for(topic: topic)
      message[:payload] = config.deserializers[:payload].decode_message_hash(message[:payload])
      if message[:key] && config.deserializers[:key].respond_to?(:decode_message_hash)
        message[:key] = config.deserializers[:key].decode_message_hash(message[:key])
      end
    end

    # Start the DB producers to send Kafka messages.
    # @param thread_count [Integer] the number of threads to start.
    # @return [void]
    def start_db_backend!(thread_count: 1)
      Sigurd.exit_on_signal = true
      if self.config.producers.backend != :db
        raise('Publish backend is not set to :db, exiting')
      end

      if thread_count.nil? || thread_count.zero?
        raise('Thread count is not given or set to zero, exiting')
      end

      producers = (1..thread_count).map do
        Deimos::Utils::OutboxProducer.
          new(self.config.outbox.logger || self.config.logger)
      end
      executor = Sigurd::Executor.new(producers,
                                      sleep_seconds: 5,
                                      logger: self.config.logger)
      signal_handler = Sigurd::SignalHandler.new(executor)
      signal_handler.run!
    end

    def setup_karafka
      Karafka.producer.middleware.append(Deimos::ProducerMiddleware)
      Karafka.monitor.notifications_bus.register_event('deimos.ar_consumer.consume_batch')
      Karafka.monitor.notifications_bus.register_event('deimos.encode_messages')
      Karafka.monitor.notifications_bus.register_event('deimos.outbox.produce')

      Karafka.producer.monitor.subscribe('error.occurred') do |event|
        if event.payload.key?(:messages)
          topic = event[:messages].first[:topic]
          config = Deimos.karafka_config_for(topic: topic)
          message = Deimos::Logging.messages_log_text(config.payload_log, event[:messages])
          Karafka.logger.error("Error producing messages: #{event[:error].message} #{message.to_json}")
        end
      end
    end

    # @return [Array<Karafka::Routing::Topic]
    def karafka_configs
      Karafka::App.routes.flat_map(&:topics).flat_map(&:to_a)
    end

    # @param topic [String]
    # @return [Karafka::Routing::Topic,nil]
    def karafka_config_for(topic: nil, producer: nil)
      if topic
        karafka_configs.find { |t| t.name == topic}
      elsif producer
        karafka_configs.find { |t| t.producer_class == producer}
      end
    end

    # @param handler_class [Class]
    # @return [String,nil]
    def topic_for_consumer(handler_class)
      Deimos.karafka_configs.each do |topic|
        if topic.consumer == handler_class
          return topic.name
        end
      end
      nil
    end

  end
end
