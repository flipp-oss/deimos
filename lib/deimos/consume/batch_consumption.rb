# frozen_string_literal: true

module Deimos
  module Consume
    # Helper methods used by batch consumers, i.e. those with "inline_batch"
    # delivery. Payloads are decoded then consumers are invoked with arrays
    # of messages to be handled at once
    module BatchConsumption
      extend ActiveSupport::Concern

      # @param batch [Array<String>]
      # @param metadata [Hash]
      # @return [void]
      def around_consume_batch(batch, metadata)
        payloads = []
        _with_span do
          benchmark = Benchmark.measure do
            if self.class.config[:key_configured]
              metadata[:keys] = batch.map do |message|
                decode_key(message.key)
              end
            end
            metadata[:first_offset] = batch.first&.offset

            payloads = batch.map do |message|
              decode_message(message.payload)
            end
            _received_batch(payloads, metadata)
            yield(payloads, metadata)
          end
          _handle_batch_success(benchmark.real, payloads, metadata)
        end
      rescue StandardError => e
        _handle_batch_error(e, payloads, metadata)
      end

      def consume_batch
        raise MissingImplementationError
      end

    protected

      # @!visibility private
      def _received_batch(messages, metadata)
        Deimos.log_info(
          message: 'Got Kafka batch event',
          message_ids: _payload_identifiers(messages),
          metadata: metadata.except(:keys)
        )
        Deimos.log_debug(
          message: 'Kafka batch event payloads',
          payloads: messages
        )
        Deimos.config.metrics&.increment(
          'handler',
          tags: %W(
            status:batch_received
            topic:#{metadata[:topic]}
          ))
        Deimos.config.metrics&.increment(
          'handler',
          by: metadata[:batch_size],
          tags: %W(
            status:received
            topic:#{metadata[:topic]}
          ))
      end

      # @!visibility private
      # @param exception [Throwable]
      # @param payloads [Array<Hash>]
      # @param metadata [Hash]
      def _handle_batch_error(exception, payloads, metadata)
        Deimos.config.metrics&.increment(
          'handler',
          tags: %W(
            status:batch_error
            topic:#{metadata[:topic]}
          ))
        Deimos.log_warn(
          message: 'Error consuming message batch',
          handler: self.class.name,
          metadata: metadata.except(:keys),
          message_ids: _payload_identifiers(payloads, metadata),
          error_message: exception.message,
          error: exception.backtrace
        )
        _error(exception, payloads, metadata)
      end

      # @!visibility private
      # @param time_taken [Float]
      # @param payloads [Array<Hash>]
      # @param metadata [Hash]
      def _handle_batch_success(time_taken, payloads, metadata)
        Deimos.config.metrics&.histogram('handler',
                                         time_taken,
                                         tags: %W(
                                           time:consume_batch
                                           topic:#{metadata[:topic]}
                                         ))
        Deimos.config.metrics&.increment(
          'handler',
          tags: %W(
            status:batch_success
            topic:#{metadata[:topic]}
          ))
        Deimos.config.metrics&.increment(
          'handler',
          by: metadata[:batch_size],
          tags: %W(
            status:success
            topic:#{metadata[:topic]}
          ))
        Deimos.log_info(
          message: 'Finished processing Kafka batch event',
          message_ids: _payload_identifiers(payloads, metadata),
          time_elapsed: time_taken,
          metadata: metadata.except(:keys)
        )
      end

      # @!visibility private
      # Get payload identifiers (key and message_id if present) for logging.
      # @param payloads [Array<Hash>]
      # @param metadata [Hash]
      # @return [Array<Array>] the identifiers.
      def _payload_identifiers(messages)
        message_ids = messages&.map do |message|
          if message.payload.is_a?(Hash) && message.payload.key?('message_id')
            message.payload['message_id']
          end
        end

        # Payloads may be nil if preprocessing failed
        messages = messages || messages.map(&:key) || []

        messages.zip(messages.map(&:key) || [], message_ids || []).map do |_, k, m_id|
          ids = {}

          ids[:key] = k if k.present?
          ids[:message_id] = m_id if m_id.present?

          ids
        end
      end
    end
  end
end
