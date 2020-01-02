# frozen_string_literal: true

require 'deimos/base_consumer'
require 'phobos/batch_handler'

module Deimos
  # Class to consume batches of messages in a topic
  # Note: According to the docs, instances of your handler will be created
  # for every incoming batch of messages. This class should be lightweight.
  class BatchConsumer < BaseConsumer
    include Phobos::BatchHandler

    # :nodoc:
    def around_consume_batch(payloads, metadata)
      _received_batch(payloads, metadata)
      benchmark = Benchmark.measure do
        _with_error_span(payloads, metadata) { yield }
      end
      _handle_success(benchmark.real, payloads, metadata)
    end

    # :nodoc:
    def before_consume_batch(batch, metadata)
      _with_error_span(batch, metadata) do
        if self.class.config[:key_configured]
          metadata[:keys] = batch.map do |message|
            decode_key(message.key)
          end
        end

        batch.map do |message|
          self.class.decoder.decode(message.payload) if message.payload.present?
        end
      end
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
    def _handle_error(exception, payloads, metadata)
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
      super
    end

    # @param time_taken [Float]
    # @param payloads [Array<Hash>]
    # @param metadata [Hash]
    def _handle_success(time_taken, payloads, metadata)
      Deimos.config.metrics&.histogram('handler', time_taken, tags: %W(
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
    # @return [Hash] the identifiers.
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
