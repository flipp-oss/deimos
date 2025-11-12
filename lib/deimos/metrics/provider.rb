# frozen_string_literal: true

module Deimos
  module Metrics
    # Base class for all metrics providers.
    class Provider
      # Send an counter increment metric
      # @param metric_name [String] The name of the counter metric
      # @param options [Hash] Any additional options, e.g. :tags
      # @return [void]
      def increment(_metric_name, _options={})
        raise MissingImplementationError
      end

      # Send an counter increment metric
      # @param metric_name [String] The name of the counter metric
      # @param count [Integer]
      # @param options [Hash] Any additional options, e.g. :tags
      # @return [void]
      def gauge(_metric_name, _count, _options={})
        raise MissingImplementationError
      end

      # Send an counter increment metric
      # @param metric_name [String] The name of the counter metric
      # @param count [Integer]
      # @param options [Hash] Any additional options, e.g. :tags
      # @return [void]
      def histogram(_metric_name, _count, _options={})
        raise MissingImplementationError
      end

      # Time a yielded block, and send a timer metric
      # @param metric_name [String] The name of the metric
      # @param options [Hash] Any additional options, e.g. :tags
      # @return [void]
      def time(_metric_name, _options={})
        raise MissingImplementationError
      end
    end
  end
end
