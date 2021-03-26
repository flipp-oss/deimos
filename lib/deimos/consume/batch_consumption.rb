# frozen_string_literal: true

module Deimos
  module Consume
    # Helper methods used by batch consumers, i.e. those with "inline_batch"
    # delivery. Payloads are decoded then consumers are invoked with arrays
    # of messages to be handled at once
    module BatchConsumption
      extend ActiveSupport::Concern
      include Phobos::BatchHandler
      include SharedConfig

      # :nodoc:
      def around_consume_batch(batch, metadata)
        payloads = []
        benchmark = Benchmark.measure do
          if self.class.config[:key_configured]
            metadata[:keys] = batch.map do |message|
              decode_key(message.key)
            end
          end
          metadata[:first_offset] = batch.first&.offset

          payloads = batch.map do |message|
            message.payload ? self.class.decoder.decode(message.payload) : nil
          end
          _received_batch(payloads, metadata)
          _with_span do
            yield payloads, metadata
          end
        end
        _handle_batch_success(benchmark.real, payloads, metadata)
      rescue StandardError => e
        _handle_batch_error(e, payloads, metadata)
      end

      # Consume a batch of incoming messages.
      # @param _payloads [Array<Phobos::BatchMessage>]
      # @param _metadata [Hash]
      def consume_batch(_payloads, _metadata)
        raise NotImplementedError
      end

    protected

      def _received_batch(payloads, metadata)
        Deimos.config.logger.info(
          message: 'Got Kafka batch event',
          message_ids: _payload_identifiers(payloads, metadata),
          metadata: metadata.except(:keys)
        )
        Deimos.config.logger.debug(
          message: 'Kafka batch event payloads',
          payloads: payloads
        )
        Deimos.config.metrics&.increment(
          'handler',
          tags: %W(
            status:batch_received
            topic:#{metadata[:topic]}
          ))
        Deimos.config.metrics&.increment(
          'handler',
          by: metadata['batch_size'],
          tags: %W(
            status:received
            topic:#{metadata[:topic]}
          ))
        if payloads.present?
          payloads.each { |payload| _report_time_delayed(payload, metadata) }
        end
      end

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
        Deimos.config.logger.warn(
          message: 'Error consuming message batch',
          handler: self.class.name,
          metadata: metadata.except(:keys),
          message_ids: _payload_identifiers(payloads, metadata),
          error_message: exception.message,
          error: exception.backtrace
        )
        _error(exception, payloads, metadata)
      end

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
          by: metadata['batch_size'],
          tags: %W(
            status:success
            topic:#{metadata[:topic]}
          ))
        Deimos.config.logger.info(
          message: 'Finished processing Kafka batch event',
          message_ids: _payload_identifiers(payloads, metadata),
          time_elapsed: time_taken,
          metadata: metadata.except(:keys)
        )
      end

      # Get payload identifiers (key and message_id if present) for logging.
      # @param payloads [Array<Hash>]
      # @param metadata [Hash]
      # @return [Array<Array>] the identifiers.
      def _payload_identifiers(payloads, metadata)
        message_ids = payloads&.map do |payload|
          if payload.is_a?(Hash) && payload.key?('message_id')
            payload['message_id']
          end
        end

        # Payloads may be nil if preprocessing failed
        messages = payloads || metadata[:keys] || []

        messages.zip(metadata[:keys] || [], message_ids || []).map do |_, k, m_id|
          ids = {}

          ids[:key] = k if k.present?
          ids[:message_id] = m_id if m_id.present?

          ids
        end
      end
    end
  end
end
