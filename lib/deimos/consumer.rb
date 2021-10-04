# frozen_string_literal: true

require 'deimos/consume/batch_consumption'
require 'deimos/consume/message_consumption'
require 'deimos/utils/schema_class_mixin'

# Class to consume messages coming from a Kafka topic
# Note: According to the docs, instances of your handler will be created
# for every incoming message/batch. This class should be lightweight.
module Deimos
  # Basic consumer class. Inherit from this class and override either consume
  # or consume_batch, depending on the delivery mode of your listener.
  # `consume` -> use `delivery :message` or `delivery :batch`
  # `consume_batch` -> use `delivery :inline_batch`
  class Consumer
    include Consume::MessageConsumption
    include Consume::BatchConsumption
    include SharedConfig
    include Utils::SchemaClassMixin

    class << self
      # @return [Deimos::SchemaBackends::Base]
      def decoder
        @decoder ||= Deimos.schema_backend(schema: config[:schema],
                                           namespace: config[:namespace])
      end

      # @return [Deimos::SchemaBackends::Base]
      def key_decoder
        @key_decoder ||= Deimos.schema_backend(schema: config[:key_schema],
                                               namespace: config[:namespace])
      end
    end

    # Helper method to decode an encoded key.
    # @param key [String]
    # @return [Object] the decoded key.
    def decode_key(key)
      return nil if key.nil?

      config = self.class.config
      unless config[:key_configured]
        raise 'No key config given - if you are not decoding keys, please use '\
          '`key_config plain: true`'
      end

      if config[:key_field]
        self.class.decoder.decode_key(key, config[:key_field])
      elsif config[:key_schema]
        self.class.key_decoder.decode(key, schema: config[:key_schema])
      else # no encoding
        key
      end
    end

    # Helper method to decode an encoded message.
    # @param payload [Object]
    # @return [Object] the decoded message.
    def decode_message(payload)
      decoded_payload = payload.nil? ? nil : self.class.decoder.decode(payload)
      return decoded_payload unless use_schema_classes?(self.class.config.to_h)

      schema_class_instance(decoded_payload, self.class.config[:schema])
    end

  private

    def _with_span
      @span = Deimos.config.tracer&.start(
        'deimos-consumer',
        resource: self.class.name.gsub('::', '-')
      )
      yield
    ensure
      Deimos.config.tracer&.finish(@span)
    end

    def _report_time_delayed(payload, metadata)
      return if payload.nil? || payload['timestamp'].blank?

      begin
        time_delayed = Time.now.in_time_zone - payload['timestamp'].to_datetime
      rescue ArgumentError
        Deimos.config.logger.info(
          message: "Error parsing timestamp! #{payload['timestamp']}"
        )
        return
      end
      Deimos.config.metrics&.histogram('handler', time_delayed, tags: %W(
                                         time:time_delayed
                                         topic:#{metadata[:topic]}
                                       ))
    end

    # Overrideable method to determine if a given error should be considered
    # "fatal" and always be reraised.
    # @param _error [Exception]
    # @param _payload [Hash]
    # @param _metadata [Hash]
    # @return [Boolean]
    def fatal_error?(_error, _payload, _metadata)
      false
    end

    # @param exception [Exception]
    # @param payload [Hash]
    # @param metadata [Hash]
    def _error(exception, payload, metadata)
      Deimos.config.tracer&.set_error(@span, exception)

      raise if Deimos.config.consumers.reraise_errors ||
               Deimos.config.consumers.fatal_error&.call(exception, payload, metadata) ||
               fatal_error?(exception, payload, metadata)
    end
  end
end
