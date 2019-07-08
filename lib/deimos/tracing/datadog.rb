# frozen_string_literal: true

require 'deimos/tracing/provider'

module Deimos
  module Tracing
    # Tracing wrapper class for Datadog.
    class Datadog < Tracing::Provider
      # :nodoc:
      def initialize(config)
        raise 'Tracing config must specify service_name' if config[:service_name].nil?

        @service = config[:service_name]
      end

      # :nodoc:
      def start(span_name, options={})
        span = ::Datadog.tracer.trace(span_name)
        span.service = @service
        span.resource = options[:resource]
        span
      end

      # :nodoc:
      def finish(span)
        span.finish
      end

      # :nodoc:
      def set_error(span, exception)
        span.set_error(exception)
      end
    end
  end
end
