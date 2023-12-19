# frozen_string_literal: true

require 'deimos/tracing/provider'

module Deimos
  module Tracing
    # Tracing wrapper class for Datadog.
    class Datadog < Tracing::Provider
      # @param config [Hash]
      def initialize(config)
        raise 'Tracing config must specify service_name' if config[:service_name].nil?

        @service = config[:service_name]
        @tracer = ::Datadog.respond_to?(:tracer) ? ::Datadog.tracer : ::Datadog::Tracing
      end

      # :nodoc:
      def start(span_name, options={})
        span = @tracer.trace(span_name)
        span.service = @service
        span.resource = options[:resource]
        span
      end

      # :nodoc:
      def finish(span)
        span.finish
      end

      # :nodoc:
      def active_span
        @tracer.active_span
      end

      # :nodoc:
      def set_error(span, exception)
        span.set_error(exception)
      end

      # :nodoc:
      def set_tag(tag, value, span=nil)
        (span || active_span).set_tag(tag, value)
      end

      # :nodoc:
      def get_tag(tag)
        active_span.get_tag(tag)
      end

    end
  end
end
