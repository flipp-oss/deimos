# frozen_string_literal: true

module Deimos
  module Tracing
    # Base class for all tracing providers.
    class Provider
      # Returns a span object and starts the trace.
      # @param span_name [String] The name of the span/trace
      # @param options [Hash] Options for the span
      # @return [Object] The span object
      def start(span_name, options={})
        raise NotImplementedError
      end

      # Finishes the trace on the span object.
      # @param span [Object] The span to finish trace on
      def finish(span)
        raise NotImplementedError
      end

      # Set an error on the span.
      # @param span [Object] The span to set error on
      # @param exception [Exception] The exception that occurred
      def set_error(span, exception)
        raise NotImplementedError
      end
    end
  end
end
