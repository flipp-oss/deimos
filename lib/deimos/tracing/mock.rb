# frozen_string_literal: true

require 'deimos/tracing/provider'

module Deimos
  module Tracing
    # Class that mocks out tracing functionality
    class Mock < Tracing::Provider
      # :nodoc:
      def initialize(logger=nil)
        @logger = logger || Logger.new(STDOUT)
        @logger.info('MockTracingProvider initialized')
      end

      # :nodoc:
      def start(span_name, _options={})
        @logger.info("Mock span '#{span_name}' started")
        {
          name: span_name,
          started_at: Time.zone.now
        }
      end

      # :nodoc:
      def finish(span)
        name = span[:name]
        start = span[:started_at]
        finish = Time.zone.now
        @logger.info("Mock span '#{name}' finished: #{start} to #{finish}")
      end

      # :nodoc:
      def active_span
        nil
      end

      # :nodoc:
      def set_tag(name, value)
        nil
      end

      # :nodoc:
      def set_error(span, exception)
        span[:exception] = exception
        name = span[:name]
        @logger.info("Mock span '#{name}' set an error: #{exception}")
      end
    end
  end
end
