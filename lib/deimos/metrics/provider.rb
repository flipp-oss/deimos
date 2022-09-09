# frozen_string_literal: true

module Deimos
  module Metrics
    # Base class for all metrics providers.
    class Provider
      # Send an counter increment metric
      # @param metric_name [String] The name of the counter metric
      # @param options [Hash] Any additional options, e.g. :tags
      # @return [void]
      def increment(metric_name, options={})
        raise NotImplementedError
      end

      # Send an counter increment metric
      # @param metric_name [String] The name of the counter metric
      # @param count [Integer]
      # @param options [Hash] Any additional options, e.g. :tags
      # @return [void]
      def gauge(metric_name, count, options={})
        raise NotImplementedError
      end

      # Send an counter increment metric
      # @param metric_name [String] The name of the counter metric
      # @param count [Integer]
      # @param options [Hash] Any additional options, e.g. :tags
      # @return [void]
      def histogram(metric_name, count, options={})
        raise NotImplementedError
      end

      # Time a yielded block, and send a timer metric
      # @param metric_name [String] The name of the metric
      # @param options [Hash] Any additional options, e.g. :tags
      # @return [void]
      def time(metric_name, options={})
        raise NotImplementedError
      end
    end
  end
end
