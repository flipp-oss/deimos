# frozen_string_literal: true

require 'deimos/metrics/provider'

module Deimos
  module Metrics
    # A Metrics wrapper class for Datadog.
    class Datadog < Metrics::Provider

      # @param config [Hash] a hash of both client and Karakfa MetricsListener configs.
      # @param logger [Logger]
      def initialize(config, logger)
        raise 'Metrics config must specify host_ip' if config[:host_ip].nil?
        raise 'Metrics config must specify host_port' if config[:host_port].nil?
        raise 'Metrics config must specify namespace' if config[:namespace].nil?

        logger.info("DatadogMetricsProvider configured with: #{config}")
        @client = ::Datadog::Statsd.new(
          config[:host_ip],
          config[:host_port],
          tags: config[:tags],
          namespace: config[:namespace]
        )
        setup_karafka(config)
        setup_waterdrop(config)
      end

      def setup_karafka(config)
        karafka_listener = ::Karafka::Instrumentation::Vendors::Datadog::MetricsListener.new do |karafka_config|
          karafka_config.client = @client
          if config[:karafka_namespace]
            karafka_config.namespace = config[:karafka_namespace]
          end
          if config[:karafka_distribution_mode]
            karafka_config.distribution_mode = config[:karafka_distribution_mode]
          end
          if config[:rd_kafka_metrics]
            karafka_config.rd_kafka_metrics = config[:rd_kafka_metrics]
          end
        end
        Karafka.monitor.subscribe(karafka_listener)
      end

      def setup_waterdrop(config)
        waterdrop_listener = ::WaterDrop::Instrumentation::Vendors::Datadog::MetricsListener.new do |waterdrop_config|
          waterdrop_config.client = @client
          if config[:karafka_namespace]
            waterdrop_config.namespace = config[:karafka_namespace]
          end
          if config[:karafka_distribution_mode]
            waterdrop_config.distribution_mode = config[:karafka_distribution_mode]
          end
          if config[:rd_kafka_metrics]
            karafka_config.rd_kafka_metrics = [] # handled in Karafka
          end
        end
        Karafka.producer.monitor.subscribe(waterdrop_listener)
      end

      # :nodoc:
      def increment(metric_name, options={})
        @client.increment(metric_name, options)
      end

      # :nodoc:
      def gauge(metric_name, count, options={})
        @client.gauge(metric_name, count, options)
      end

      # :nodoc:
      def histogram(metric_name, count, options={})
        @client.histogram(metric_name, count, options)
      end

      # :nodoc:
      def time(metric_name, options={})
        @client.time(metric_name, options) do
          yield
        end
      end
    end
  end
end
