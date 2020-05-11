# frozen_string_literal: true

require 'deimos/base_consumer'
require 'deimos/shared_config'
require 'phobos/handler'
require 'active_support/all'

# Class to consume messages coming from the pipeline topic
# Note: According to the docs, instances of your handler will be created
# for every incoming message. This class should be lightweight.
module Deimos
  # Parent consumer class.
  class Consumer < BaseConsumer
    include Phobos::Handler

    # :nodoc:
    def around_consume(payload, metadata)
      decoded_payload = payload.dup
      new_metadata = metadata.dup
      benchmark = Benchmark.measure do
        _with_span do
          new_metadata[:key] = decode_key(metadata[:key]) if self.class.config[:key_configured]
          decoded_payload = payload ? self.class.decoder.decode(payload) : nil
          _received_message(decoded_payload, new_metadata)
          yield decoded_payload, new_metadata
        end
      end
      _handle_success(benchmark.real, decoded_payload, new_metadata)
    rescue StandardError => e
      _handle_error(e, decoded_payload, new_metadata)
    end

    # Consume incoming messages.
    # @param _payload [String]
    # @param _metadata [Hash]
    def consume(_payload, _metadata)
      raise NotImplementedError
    end

  private

    def _received_message(payload, metadata)
      Deimos.config.logger.info(
        message: 'Got Kafka event',
        payload: payload,
        metadata: metadata
      )
      Deimos.config.metrics&.increment('handler', tags: %W(
                                         status:received
                                         topic:#{metadata[:topic]}
                                       ))
      _report_time_delayed(payload, metadata)
    end

    # @param exception [Throwable]
    # @param payload [Hash]
    # @param metadata [Hash]
    def _handle_error(exception, payload, metadata)
      Deimos.config.metrics&.increment(
        'handler',
        tags: %W(
          status:error
          topic:#{metadata[:topic]}
        )
      )
      Deimos.config.logger.warn(
        message: 'Error consuming message',
        handler: self.class.name,
        metadata: metadata,
        data: payload,
        error_message: exception.message,
        error: exception.backtrace
      )
      super
    end

    # @param time_taken [Float]
    # @param payload [Hash]
    # @param metadata [Hash]
    def _handle_success(time_taken, payload, metadata)
      Deimos.config.metrics&.histogram('handler', time_taken, tags: %W(
                                         time:consume
                                         topic:#{metadata[:topic]}
                                       ))
      Deimos.config.metrics&.increment('handler', tags: %W(
                                         status:success
                                         topic:#{metadata[:topic]}
                                       ))
      Deimos.config.logger.info(
        message: 'Finished processing Kafka event',
        payload: payload,
        time_elapsed: time_taken,
        metadata: metadata
      )
    end
  end
end
