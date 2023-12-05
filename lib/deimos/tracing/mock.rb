# frozen_string_literal: true

require 'deimos/tracing/provider'

module Deimos
  module Tracing
    # Class that mocks out tracing functionality
    class Mock < Tracing::Provider
      # @param logger [Logger]
      def initialize(logger=nil)
        @logger = logger || Logger.new(STDOUT)
        @logger.info('MockTracingProvider initialized')
        @active_span = MockSpan.new
      end

      # @param span_name [String]
      # @param _options [Hash]
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
        @active_span ||= MockSpan.new
      end

      # :nodoc:
      def set_tag(tag, value, span=nil)
        if span
          span.set_tag(tag, value)
        else
          @span.set_tag(tag, value)
        end
      end

      # Get a tag from a span with the specified tag.
      # @param tag [String]
      def get_tag(tag)
        @span.get_tag(tag)
      end

      # :nodoc:
      def set_error(span, exception)
        span[:exception] = exception
        name = span[:name]
        @logger.info("Mock span '#{name}' set an error: #{exception}")
      end
    end

    # Mock Span class
    class MockSpan
      # :nodoc:
      def initialize
        @span = {}
      end

      # :nodoc:
      def set_tag(tag, value)
        @span[tag] = value
      end

      # :nodoc:
      def get_tag(tag)
        @span[tag]
      end
    end
  end
end
