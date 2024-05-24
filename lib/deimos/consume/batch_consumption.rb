# frozen_string_literal: true

module Deimos
  module Consume
    # Helper methods used by batch consumers, i.e. those with "inline_batch"
    # delivery. Payloads are decoded then consumers are invoked with arrays
    # of messages to be handled at once
    module BatchConsumption
      extend ActiveSupport::Concern

      def consume_batch
        raise MissingImplementationError
      end

    protected

      def _consume_batch
        _with_span do
          begin
            benchmark = Benchmark.measure do
              consume_batch
            end
            _handle_batch_success(benchmark.real)
          rescue StandardError => e
            _handle_batch_error(e)
          end
        end
      end

      # @!visibility private
      # @param exception [Throwable]
      def _handle_batch_error(exception)
        Deimos::Logging.log_warn(
          message: 'Error consuming message batch',
          handler: self.class.name,
          metadata: Deimos::Logging.metadata_log_text(messages.metadata),
          messages: Deimos::Logging.messages_log_text(self.topic.payload_log, messages),
          error_message: exception.message,
          error: exception.backtrace
        )
        _error(exception, messages)
      end

      # @!visibility private
      # @param time_taken [Float]
      def _handle_batch_success(time_taken)
        Deimos::Logging.log_info(
          message: 'Finished processing Kafka batch event',
          message_ids: Deimos::Logging.messages_log_text(self.topic.payload_log, messages),
          time_elapsed: time_taken,
          metadata: Deimos::Logging.metadata_log_text(messages.metadata)
        )
      end

    end
  end
end
