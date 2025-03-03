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
        raise MissingImplementationError
      end

      # Finishes the trace on the span object.
      # @param span [Object] The span to finish trace on
      # @return [void]
      def finish(span)
        raise MissingImplementationError
      end

      # Set an error on the span.
      # @param span [Object] The span to set error on
      # @param exception [Exception] The exception that occurred
      # @return [void]
      def set_error(span, exception)
        raise MissingImplementationError
      end

      # Get the currently activated span.
      # @return [Object]
      def active_span
        raise MissingImplementationError
      end

      # Set a tag to a span. Use the currently active span if not given.
      # @param tag [String]
      # @param value [String]
      # @param span [Object]
      # @return [void]
      def set_tag(tag, value, span=nil)
        raise MissingImplementationError
      end

      # Get a tag from a span with the specified tag.
      # @param tag [String]
      def get_tag(tag)
        raise MissingImplementationError
      end

    end
  end
end
