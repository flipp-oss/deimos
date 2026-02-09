# frozen_string_literal: true

require 'deimos/transcoder'
require 'deimos/ext/producer_middleware'
require 'deimos/schema_backends/plain'

module Deimos
  class SchemaRoute < Karafka::Routing::Features::Base

    module Topic
      {
        schema: nil,
        namespace: nil,
        key_config: { none: true },
        schema_backend: nil,
        registry_url: nil,
        registry_user: nil,
        registry_password: nil,
        use_schema_classes: nil
      }.each do |field, default|
        define_method(field) do |*args|
          @_deimos_config ||= {}
          @_deimos_config[:schema] ||= {}
          if args.any?
            @_deimos_config[:schema][field] = args[0]
            _deimos_setup_transcoders if schema && namespace
          end
          @_deimos_config[:schema][field] || default
        end
      end
      def _deimos_setup_transcoders # rubocop:disable Metrics/AbcSize
        use_classes = if use_schema_classes.nil?
                        Deimos.config.schema.use_schema_classes
                      else
                        use_schema_classes
                      end
        registry_info = if registry_url
                          Deimos::RegistryInfo.new(registry_url, registry_user, registry_password)
                        else
                          nil
                        end
        payload = Transcoder.new(
          schema: schema,
          namespace: namespace,
          backend: schema_backend,
          use_schema_classes: use_classes,
          topic: name,
          registry_info: registry_info
        )

        key = nil

        if key_config[:plain]
          key = Transcoder.new(
            schema: schema,
            backend: nil,
            namespace: namespace,
            use_schema_classes: use_classes,
            topic: name,
            registry_info: registry_info
          )
          key.backend_type = :plain
        elsif !key_config[:none]
          if key_config[:field]
            key = Transcoder.new(
              schema: schema,
              backend: schema_backend,
              namespace: namespace,
              use_schema_classes: use_classes,
              key_field: key_config[:field].to_s,
              topic: name,
              registry_info: registry_info
            )
          elsif key_config[:schema]
            key = Transcoder.new(
              schema: key_config[:schema] || schema,
              backend: schema_backend,
              namespace: namespace,
              use_schema_classes: use_classes,
              topic: self.name,
              registry_info: registry_info
            )
          else
            raise 'No key config given - if you are not encoding keys, please use `key_config plain: true`'
          end
        end
        deserializers.payload = payload
        deserializers.key = key if key
      end
    end
  end
end

Deimos::SchemaRoute.activate
