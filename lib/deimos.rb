# frozen_string_literal: true

require 'avro-patches'
require 'avro_turf'
require 'phobos'
require 'deimos/version'
require 'deimos/config/configuration'
require 'deimos/avro_data_encoder'
require 'deimos/avro_data_decoder'
require 'deimos/producer'
require 'deimos/active_record_producer'
require 'deimos/active_record_consumer'
require 'deimos/consumer'
require 'deimos/batch_consumer'
require 'deimos/instrumentation'
require 'deimos/utils/lag_reporter'

require 'deimos/publish_backend'
require 'deimos/backends/kafka'
require 'deimos/backends/kafka_async'
require 'deimos/backends/test'

require 'deimos/monkey_patches/ruby_kafka_heartbeat'
require 'deimos/monkey_patches/schema_store'
require 'deimos/monkey_patches/phobos_producer'
require 'deimos/monkey_patches/phobos_cli'

require 'deimos/railtie' if defined?(Rails)
if defined?(ActiveRecord)
  require 'deimos/kafka_source'
  require 'deimos/kafka_topic_info'
  require 'deimos/backends/db'
  require 'deimos/utils/signal_handler.rb'
  require 'deimos/utils/executor.rb'
  require 'deimos/utils/db_producer.rb'
end
require 'deimos/utils/inline_consumer'
require 'yaml'
require 'erb'

# Parent module.
module Deimos
  class << self
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
      executor = Deimos::Utils::Executor.new(producers,
                                             sleep_seconds: 5,
                                             logger: self.config.logger)
      signal_handler = Deimos::Utils::SignalHandler.new(executor)
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
