# frozen_string_literal: true

module Deimos
  module Consume
    # Methods used by message-by-message (non-batch) consumers. These consumers
    # are invoked for every individual message.
    module MessageConsumption
      extend ActiveSupport::Concern

      # Consume incoming messages.
      # @param _message [Karafka::Messages::Message]
      # @return [void]
      def consume_message(_message)
        raise MissingImplementationError
      end

    private

      def _consume_messages
        messages.each do |message|
          begin
            _with_span do
              _received_message(message)
              benchmark = Benchmark.measure do
                consume_message(message)
              end
              _handle_success(message, benchmark.real)
            rescue StandardError => e
              _handle_message_error(e, message)
            end
          end
        end
      end

      def _received_message(message)
        Deimos::Logging.log_info(
          message: 'Got Kafka event',
          payload: message.payload,
          metadata: Deimos::Logging.metadata_log_text(message.metadata)
        )
      end

      # @param exception [Throwable]
      # @param message [Karafka::Messages::Message]
      def _handle_message_error(exception, message)
        Deimos::Logging.log_warn(
          message: 'Error consuming message',
          handler: self.class.name,
          metadata: Deimos::Logging.metadata_log_text(message.metadata),
          key: message.key,
          data: message.payload,
          error_message: exception.message,
          error: exception.backtrace
        )

        _error(exception, Karafka::Messages::Messages.new([message], messages.metadata))
      end

      def _handle_success(message, benchmark)
        mark_as_consumed(message)
        Deimos::Logging.log_info(
          message: 'Finished processing Kafka event',
          payload: message.payload,
          time_elapsed: benchmark,
          metadata: Deimos::Logging.metadata_log_text(message.metadata)
        )
      end
    end
  end
end
