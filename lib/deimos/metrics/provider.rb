# frozen_string_literal: true

# rubocop:disable Lint/UnusedMethodArgument
module Deimos
  module Metrics
    # Base class for all metrics providers.
    class Provider
      # Send an counter increment metric
      # @param metric_name [String] The name of the counter metric
      # @param options [Hash] Any additional options, e.g. :tags
      def increment(metric_name, options={})
        raise NotImplementedError
      end

      # Send an counter increment metric
      # @param metric_name [String] The name of the counter metric
      # @param options [Hash] Any additional options, e.g. :tags
      def gauge(metric_name, count, options={})
        raise NotImplementedError
      end

      # Send an counter increment metric
      # @param metric_name [String] The name of the counter metric
      # @param options [Hash] Any additional options, e.g. :tags
      def histogram(metric_name, count, options={})
        raise NotImplementedError
      end

      # Time a yielded block, and send a timer metric
      # @param metric_name [String] The name of the metric
      # @param options [Hash] Any additional options, e.g. :tags
      def time(metric_name, options={})
        raise NotImplementedError
      end
    end
  end
end
# rubocop:enable Lint/UnusedMethodArgument
