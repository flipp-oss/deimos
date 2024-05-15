module Deimos

  class ProducerConfig
    attr_accessor :topic, :encoder, :key_encoder, :key_field

    # @param topic [Karafka::Routing::Topic]
    # @param transcoders [Hash<Symbol, Deimos::Transcoder>]
    def initialize(topic, payload, key)
      self.topic = topic
      self.encoder = payload
      self.key_encoder = key
      self.key_field = key_encoder&.key_field
    end
  end

  module ProducerMiddleware
    class << self

      # @return [Hash<String, ProducerConfig>]
      attr_accessor :producer_configs

      def call(message)
        config = producer_configs[message[:topic]]
        return message if config.nil?

        m = Deimos::Message.new(message[:payload].to_h, headers: message[:headers])
        _process_message(m, message, config)
        message[:payload] = m.encoded_payload
        message[:key] = m.encoded_key
        message[:topic] ||= "#{Deimos.config.producers.topic_prefix}#{config.topic.name}"
        message
      end

      # @param message [Deimos::Message]
      # @param karafka_message [Hash]
      # @param config [Deimos::ProducerConfig]
      def _process_message(message, karafka_message, config)
        encoder = config.encoder.backend
        # this violates the Law of Demeter but it has to happen in a very
        # specific order and requires a bunch of methods on the producer
        # to work correctly.
        message.add_fields(encoder.schema_fields.map(&:name))
        message.key = _retrieve_key(message.payload, config) || karafka_message[:key]
        # need to do this before _coerce_fields because that might result
        # in an empty payload which is an *error* whereas this is intended.
        message.payload = nil if message.payload.blank?
        message.coerce_fields(encoder)
        message.encoded_key = _encode_key(message.key, config)
        message.topic = config.topic.name
        message.encoded_payload = if message.payload.nil?
                                    nil
                                  else
                                    encoder.encode(message.payload,
                                                   topic: "#{Deimos.config.producers.topic_prefix}#{config.topic.name}-value")
                                  end
      end

      # @param key [Object]
      # @param config [ProducerConfig]
      # @return [String|Object]
      def _encode_key(key, config)
        if config.key_encoder
          config.key_encoder.encode_key(key)
        elsif key
          config.encoder.encode(key)
        else
          key
        end
      end

      # @param payload [Hash]
      # @param config [ProducerConfig]
      # @return [String]
      def _retrieve_key(payload, config)
        key = payload.delete(:payload_key)
        return key if key

        config.key_field ? payload[config.key_field] : nil
      end
    end
  end
end
