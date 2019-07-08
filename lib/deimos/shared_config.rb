# frozen_string_literal: true

require 'active_support/concern'

module Deimos
  # Module that producers and consumers can share which sets up configuration.
  module SharedConfig
    extend ActiveSupport::Concern

    # need to use this instead of class_methods to be backwards-compatible
    # with Rails 3
    module ClassMethods
      # @return [Hash]
      def config
        return @config if @config

        @config = {
          encode_key: true
        }
        klass = self.superclass
        while klass.respond_to?(:config)
          klass_config = klass.config
          if klass_config
            # default is true for this so don't include it in the merge
            klass_config.delete(:encode_key) if klass_config[:encode_key]
            @config.merge!(klass_config) if klass.config
          end
          klass = klass.superclass
        end
        @config
      end

      # Set the schema.
      # @param schema [String]
      def schema(schema)
        config[:schema] = schema
      end

      # Set the namespace.
      # @param namespace [String]
      def namespace(namespace)
        config[:namespace] = namespace
      end

      # Set key configuration.
      # @param field [Symbol] the name of a field to use in the value schema as
      #   a generated key schema
      # @param schema [String|Symbol] the name of a schema to use for the key
      # @param plain [Boolean] if true, do not encode keys at all
      # @param none [Boolean] if true, do not use keys at all
      def key_config(plain: nil, field: nil, schema: nil, none: nil)
        config[:no_keys] = none
        config[:encode_key] = !plain && !none
        config[:key_field] = field&.to_s
        config[:key_schema] = schema
      end
    end
  end
end
