# frozen_string_literal: true

# This is just so that < Deimos::Consumer can still be used
module Deimos
  class Consumer
    include SharedConfig

    def consume(_payload, _metadata)
      raise NotImplementedError
    end

    class << self
      def decode_key(key)
        return nil if key.nil?

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

      # Schema and namespace are not topic dependent
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
  end
end
