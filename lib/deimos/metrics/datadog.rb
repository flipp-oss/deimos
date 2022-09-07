# frozen_string_literal: true

require 'deimos/metrics/provider'

module Deimos
  module Metrics
    # A Metrics wrapper class for Datadog.
    class Datadog < Metrics::Provider
      # @param config [Hash]
      # @param logger [Logger]
      def initialize(config, logger)
        raise 'Metrics config must specify host_ip' if config[:host_ip].nil?
        raise 'Metrics config must specify host_port' if config[:host_port].nil?
        raise 'Metrics config must specify namespace' if config[:namespace].nil?

        logger.info("DatadogMetricsProvider configured with: #{config}")
        @client = ::Datadog::Statsd.new(
          config[:host_ip],
          config[:host_port]
        )
        @client.tags = config[:tags]
        @client.namespace = config[:namespace]
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
