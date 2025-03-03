module Deimos

  module ProducerMiddleware
    class << self

      def call(message)
        Karafka.monitor.instrument(
          'deimos.encode_message',
          producer: self,
          message: message
        ) do
          config = Deimos.karafka_config_for(topic: message[:topic])
          return message if config.nil? || config.schema.nil?
          return if message[:payload] && !message[:payload].is_a?(Hash) && !message[:payload].is_a?(SchemaClass::Record)

          m = Deimos::Message.new(message[:payload].to_h,
                                  headers: message[:headers],
                                  partition_key: message[:partition_key])
          _process_message(m, message, config)
          message[:payload] = m.encoded_payload
          message[:label] = {
            original_payload: m.payload,
            original_key: m.key
          }
          message[:key] = m.encoded_key
          message[:partition_key] = if m.partition_key
                                      m.partition_key.to_s
                                    elsif m.key
                                      m.key.to_s
                                    else
                                      nil
                                    end
          message[:topic] = "#{Deimos.config.producers.topic_prefix}#{config.name}"

          validate_key_config(config, message)

          message
        end
      end

      def validate_key_config(config, message)
        if message[:key].nil? && config.deserializers[:key].is_a?(Deimos::Transcoder)
           raise 'No key given but a key is required! Use `key_config none: true` to avoid using keys.'
        end
      end

      # @param message [Deimos::Message]
      # @param karafka_message [Hash]
      # @param config [Deimos::ProducerConfig]
      def _process_message(message, karafka_message, config)
        encoder = config.deserializers[:payload].backend
        key_transcoder = config.deserializers[:key]
        # this violates the Law of Demeter but it has to happen in a very
        # specific order and requires a bunch of methods on the producer
        # to work correctly.
        message.add_fields(encoder.schema_fields.map(&:name))
        message.key = karafka_message[:key] || _retrieve_key(message.payload, key_transcoder)
        # need to do this before _coerce_fields because that might result
        # in an empty payload which is an *error* whereas this is intended.
        message.payload = nil if message.payload.blank?
        message.coerce_fields(encoder)
        message.encoded_key = _encode_key(message.key, config)
        message.topic = config.name
        message.encoded_payload = if message.payload.nil?
                                    nil
                                  else
                                    encoder.encode(message.payload,
                                                   topic: "#{Deimos.config.producers.topic_prefix}#{config.name}-value")
                                  end
      end

      # @param key [Object]
      # @param config [ProducerConfig]
      # @return [String|Object]
      def _encode_key(key, config)
        return nil if key.nil?

        if config.deserializers[:key].respond_to?(:encode_key)
          config.deserializers[:key].encode_key(key)
        elsif key
          config.deserializers[:payload].encode(key)
        else
          key
        end
      end

      # @param payload [Hash]
      # @param key_transcoder [Deimos::Transcoder]
      # @return [String]
      def _retrieve_key(payload, key_transcoder)
        key = payload.delete(:payload_key)
        return key if key || !key_transcoder.respond_to?(:key_field)

        key_transcoder.key_field ? payload[key_transcoder.key_field] : nil
      end
    end
  end
end
