# frozen_string_literal: true

module Deimos
  module Consume
    # Methods used by message-by-message (non-batch) consumers. These consumers
    # are invoked for every individual message.
    module MessageConsumption
      extend ActiveSupport::Concern

      # @param payload [String]
      # @param metadata [Hash]
      # @return [void]
      def around_consume(payload, metadata)
        decoded_payload = payload.nil? ? nil : payload.dup
        new_metadata = metadata.dup
        benchmark = Benchmark.measure do
          _with_span do
            new_metadata[:key] = decode_key(metadata[:key]) if self.class.config[:key_configured]
            decoded_payload = decode_message(payload)
            yield(decoded_payload, new_metadata)
          end
        end
        _handle_success(benchmark.real, decoded_payload, new_metadata)
      rescue StandardError => e
        _handle_error(e, decoded_payload, new_metadata)
      end

      # Consume incoming messages.
      # @param _message [Karafka::Messages::Message]
      # @return [void]
      def consume_message(_message)
        raise MissingImplementationError
      end

    private

      def _received_message(message)
        Deimos.log_info(
          message: 'Got Kafka event',
          payload: message.payload,
          metadata: message.metadata
        )
        Deimos.config.metrics&.increment('handler', tags: %W(
                                           status:received
                                           topic:#{topic.name}
                                         ))
        _report_time_delayed(message)
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
        Deimos.log_warn(
          message: 'Error consuming message',
          handler: self.class.name,
          metadata: metadata,
          data: payload,
          error_message: exception.message,
          error: exception.backtrace
        )

        _error(exception, payload, metadata)
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
        Deimos.log_info(
          message: 'Finished processing Kafka event',
          payload: payload,
          time_elapsed: time_taken,
          metadata: metadata
        )
      end
    end
  end
end
