module Deimos
  class Transcoder

    attr_accessor :key_field

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

    def backend
      @backend ||= Deimos.schema_backend(schema: @schema,
                                         namespace: @namespace)
    end

    # for use in test helpers
    def encode_key(key)
      self.backend.encode_key(self.key_field, key, topic: @topic)
    end

    def decode_key(key)
      return nil if key.nil? || self.key_field.nil?

      decoded_key = self.backend.decode_key(key, self.key_field)
      return decoded_key unless Utils::SchemaClass.use?(@use_schema_classes)

      Utils::SchemaClass.instance(decoded_key,
                                  "#{@schema}_key",
                                  @namespace)
    end

    def decode_message(payload)
      return nil if payload.nil?

      decoded_payload = self.backend.decode(payload)
      return decoded_payload unless Utils::SchemaClass.use?(@use_schema_classes)

      Utils::SchemaClass.instance(decoded_payload,
                                  @schema,
                                  @namespace)
    end

    def encode(payload)
      return nil if payload.nil?

      self.backend.encode(payload.to_h)
    end

    # @param message [Karafka::Messages::Message]
    def call(message)
      self.key_field ? decode_key(message.metadata.raw_key) : decode_message(message.raw_payload)
    end
  end
end
