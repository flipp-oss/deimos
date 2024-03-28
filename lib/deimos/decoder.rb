module Deimos
  class Decoder
    attr_accessor :key_config

    def initialize(schema:, namespace:, key_config: nil, use_schema_classes: nil)
      @schema = schema
      @namespace = namespace
      @key_config = key_config
      @use_schema_classes = use_schema_classes
    end

    def backend
      @backend ||= Deimos.schema_backend(schema: @schema,
                                         namespace: @namespace)
    end

    def decode_key(key)
      return nil if key.nil?

      if @key_config[:schema]
        self.backend.decode(key, schema: @key_config[:schema])
      elsif @key_config[:field]
        self.backend.decode_key(key, @key_config[:field])
      else
        raise "Could not decode #{key}: Unknown field config #{@key_config}"
      end
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
      @key_config ? decode_key(message.key) : decode_message(message.payload)
    end
  end
end
