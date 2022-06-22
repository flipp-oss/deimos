# frozen_string_literal: true

require 'deimos/metrics/provider'

module Deimos
  module Metrics
    # A mock Metrics wrapper which just logs the metrics
    class Mock
      # :nodoc:
      def initialize(logger=nil)
        @logger = logger || Logger.new($stdout)
        @logger.info('MockMetricsProvider initialized')
      end

      # :nodoc:
      def increment(metric_name, options={})
        @logger.info("MockMetricsProvider.increment: #{metric_name}, #{options}")
      end

      # :nodoc:
      def gauge(metric_name, count, options={})
        @logger.info("MockMetricsProvider.gauge: #{metric_name}, #{count}, #{options}")
      end

      # :nodoc:
      def histogram(metric_name, count, options={})
        @logger.info("MockMetricsProvider.histogram: #{metric_name}, #{count}, #{options}")
      end

      # :nodoc:
      def time(metric_name, options={})
        start_time = Time.now
        yield
        total_time = (Time.now - start_time).to_i
        @logger.info("MockMetricsProvider.time: #{metric_name}, #{total_time}, #{options}")
      end
    end
  end
end
