module Deimos
  class Decoder
    attr_accessor :key_config

    # @param schema [String]
    # @param namespace [String]
    # @param key_field [Symbol]
    # @param use_schema_classes [Boolean]
    def initialize(schema:, namespace:, key_field: nil, use_schema_classes: nil)
      @schema = schema
      @namespace = namespace
      @key_field = key_field
      @use_schema_classes = use_schema_classes
    end

    def backend
      @backend ||= Deimos.schema_backend(schema: @schema,
                                         namespace: @namespace)
    end

    def decode_key(key)
      return nil if key.nil? || @key_field.nil?

      decoded_key = self.backend.decode_key(key, @key_field)
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

    # @param message [Karafka::Messages::Message]
    def call(message)
      @key_field ? decode_key(message.key) : decode_message(message.payload)
    end
  end
end
