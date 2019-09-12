# frozen_string_literal: true

module Deimos
  # Class to hold configuration.
  class Configuration
    # @return [Logger]
    attr_accessor :logger
    attr_accessor :phobos_logger
    attr_accessor :kafka_logger

    # By default, consumer errors will be consumed and logged to
    # the metrics provider.
    # Set this to true to force the error to be raised.
    # @return [Boolean]
    attr_accessor :reraise_consumer_errors

    # @return [String]
    attr_accessor :schema_registry_url

    # @return [String]
    attr_accessor :seed_broker

    # Local path to schemas.
    # @return [String]
    attr_accessor :schema_path

    # Default namespace for all producers. Can remain nil. Individual
    # producers can override.
    # @return [String]
    attr_accessor :producer_schema_namespace

    # Add a prefix to all topic names. This can be useful if you're using
    # the same Kafka broker for different environments that are producing
    # the same topics.
    # @return [String]
    attr_accessor :producer_topic_prefix

    # Disable all actual message producing. Useful when doing things like
    # mass imports or data space management when events don't need to be
    # fired.
    # @return [Boolean]
    attr_accessor :disable_producers

    # File path to the Phobos configuration file, relative to the application root.
    # @return [String]
    attr_accessor :phobos_config_file

    # @return [Boolean]
    attr_accessor :ssl_enabled

    # @return [String]
    attr_accessor :ssl_ca_cert

    # @return [String]
    attr_accessor :ssl_client_cert

    # @return [String]
    attr_accessor :ssl_client_cert_key

    # Currently can be set to :db, :kafka, or :async_kafka. If using Kafka
    # directly, set to async in your user-facing app, and sync in your
    # consumers or delayed workers.
    # @return [Symbol]
    attr_accessor :publish_backend

    # @return [Boolean]
    attr_accessor :report_lag

    # @return [Metrics::Provider]
    attr_accessor :metrics

    # @return [Tracing::Provider]
    attr_accessor :tracer

    # For internal purposes only
    # @return [Block]
    attr_accessor :fatal_error_block

    # :nodoc:
    def initialize
      @phobos_config_file = 'config/phobos.yml'
      @publish_backend = :kafka_async
      fatal_error { false }
    end

    # Block taking an exception, payload and metadata and returning
    # true if this should be considered a fatal error and false otherwise.
    # Not needed if reraise_consumer_errors is set to true.
    def fatal_error(&block)
      @fatal_error_block = block
    end

    # @param other_config [Configuration]
    # @return [Boolean]
    def phobos_config_changed?(other_config)
      phobos_keys = %w(seed_broker phobos_config_file ssl_ca_cert ssl_client_cert ssl_client_cert_key)
      return true if phobos_keys.any? { |key| self.send(key) != other_config.send(key) }

      other_config.logger != self.logger
    end
  end
end
