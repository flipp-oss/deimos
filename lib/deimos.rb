# frozen_string_literal: true

require 'active_support'

require 'phobos'
require 'deimos/version'
require 'deimos/config/configuration'
require 'deimos/producer'
require 'deimos/active_record_producer'
require 'deimos/active_record_consumer'
require 'deimos/consumer'
require 'deimos/batch_consumer'
require 'deimos/instrumentation'
require 'deimos/utils/lag_reporter'

require 'deimos/backends/base'
require 'deimos/backends/kafka'
require 'deimos/backends/kafka_async'
require 'deimos/backends/test'

require 'deimos/schema_backends/base'
require 'deimos/schema_enum'
require 'deimos/schema_record'

require 'deimos/monkey_patches/phobos_producer'
require 'deimos/monkey_patches/phobos_cli'

require 'deimos/railtie' if defined?(Rails)
require 'deimos/utils/schema_controller_mixin' if defined?(ActionController)

if defined?(ActiveRecord)
  require 'deimos/kafka_source'
  require 'deimos/kafka_topic_info'
  require 'deimos/backends/db'
  require 'sigurd/signal_handler'
  require 'sigurd/executor'
  require 'deimos/utils/db_producer'
  require 'deimos/utils/db_poller'
end

require 'deimos/utils/inline_consumer'
require 'yaml'
require 'erb'

# Parent module.
module Deimos
  class << self
    # @return [Class < Deimos::SchemaBackends::Base]
    def schema_backend_class
      backend = Deimos.config.schema.backend.to_s

      require "deimos/schema_backends/#{backend}"

      "Deimos::SchemaBackends::#{backend.classify}".constantize
    end

    # @param schema [String|Symbol]
    # @param namespace [String]
    # @return [Deimos::SchemaBackends::Base]
    def schema_backend(schema:, namespace:)
      schema_backend_class.new(schema: schema, namespace: namespace)
    end

    # Start the DB producers to send Kafka messages.
    # @param thread_count [Integer] the number of threads to start.
    def start_db_backend!(thread_count: 1)
      if self.config.producers.backend != :db
        raise('Publish backend is not set to :db, exiting')
      end

      if thread_count.nil? || thread_count.zero?
        raise('Thread count is not given or set to zero, exiting')
      end

      producers = (1..thread_count).map do
        Deimos::Utils::DbProducer.
          new(self.config.db_producer.logger || self.config.logger)
      end
      executor = Sigurd::Executor.new(producers,
                                      sleep_seconds: 5,
                                      logger: self.config.logger)
      signal_handler = Sigurd::SignalHandler.new(executor)
      signal_handler.run!
    end
  end
end

at_exit do
  begin
    Deimos::Backends::KafkaAsync.shutdown_producer
    Deimos::Backends::Kafka.shutdown_producer
  rescue StandardError => e
    Deimos.config.logger.error(
      "Error closing producer on shutdown: #{e.message} #{e.backtrace.join("\n")}"
    )
  end
end
