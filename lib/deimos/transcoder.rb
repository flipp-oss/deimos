module Deimos
  class Transcoder

    attr_accessor :key_field, :backend

    # @param schema [String]
    # @param namespace [String]
    # @param key_field [Symbol]
    # @param use_schema_classes [Boolean]
    # @param topic [String]
    def initialize(schema:, namespace:, key_field: nil, use_schema_classes: nil, topic: nil)
      @schema = schema
      @namespace = namespace
      self.key_field = key_field
      @use_schema_classes = use_schema_classes
      @topic = topic
    end

    # @return [Class < Deimos::SchemaBackends::Base]
    def backend
      @backend ||= Deimos.schema_backend(schema: @schema, namespace: @namespace, use_schema_classes: @use_schema_classes)
    end

    # for use in test helpers
    # @param key [Object]
    # @return [String]
    def encode_key(key)
      if self.key_field
        self.backend.encode_key(self.key_field, key, topic: @topic)
      else
        self.backend.encode(key, topic: @topic)
      end
    end

    # @param key [String]
    # @return [Object]
    def decode_key(key)
      return nil if key.nil? || self.key_field.nil?

      decoded_key = self.backend.decode_key(key, self.key_field)
      return decoded_key unless @use_schema_classes

      Utils::SchemaClass.instance(decoded_key,
                                  "#{@schema}_key",
                                  @namespace)
    end

    # @param payload [String]
    # @return [Object]
    def decode_message(payload)
      return nil if payload.nil?

      decoded_payload = self.backend.decode(payload)
      return decoded_payload unless @use_schema_classes

      Utils::SchemaClass.instance(decoded_payload,
                                  @schema,
                                  @namespace)
    end

    # @param payload [Object]
    # @return [String]
    def encode(payload)
      return nil if payload.nil?

      self.backend.encode(payload)
    end

    # @param message [Karafka::Messages::Message]
    # @return [Object]
    def call(message)
      if self.key_field
        decode_key(message.raw_key)
      elsif message.respond_to?(:raw_payload)
        decode_message(message.raw_payload)
      else
        decode_message(message.raw_key)
      end
    end

    # @param payload [String]
    # @return [Object]
    def decode_message_hash(payload)
      self.key_field ? decode_key(payload) : decode_message(payload)
    end

  end
end
