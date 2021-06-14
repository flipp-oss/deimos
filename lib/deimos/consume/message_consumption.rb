# frozen_string_literal: true

require 'deimos/utils/schema_class_mixin'

module Deimos
  module Consume
    # Methods used by message-by-message (non-batch) consumers. These consumers
    # are invoked for every individual message.
    module MessageConsumption
      extend ActiveSupport::Concern
      include Phobos::Handler
      include SharedConfig
      include Utils::SchemaClassMixin

      # :nodoc:
      # TODO: need to handle decoding logic here..! Use the Schema Classes?
      def around_consume(payload, metadata)
        decoded_payload = payload.nil? ? nil : payload.dup
        new_metadata = metadata.dup
        benchmark = Benchmark.measure do
          _with_span do
            new_metadata[:key] = decode_key(metadata[:key]) if self.class.config[:key_configured]
            decoded_payload = payload ? self.class.decoder.decode(payload) : nil
            if Deimos.config.consumers.use_schema_class
              # this 'config' comes from SharedConfig
              class_name = classified_schema(self.class.config[:schema])
              # Needs "Deimos::" in front of it for the whole namespace
              # Might want to use safe_constantize
              klass = "Deimos::#{class_name}".constantize
              # Does not correctly handle some stuff around optional payloads.
              # Does not initialize from HASH object!!!!!!!
              # want to init klass with payload. Should make this instance the decoded_payload!
              return true
            end
            _received_message(decoded_payload, new_metadata)
            # Would need to do some work here around the DECODED payload here...!
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
        Deimos.config.logger.info(
          message: 'Finished processing Kafka event',
          payload: payload,
          time_elapsed: time_taken,
          metadata: metadata
        )
      end
    end
  end
end
