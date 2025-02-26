require "deimos/transcoder"
require "deimos/ext/producer_middleware"
require "deimos/schema_backends/plain"

module Deimos
  class SchemaRoute < Karafka::Routing::Features::Base

    module Topic
      {
        schema: nil,
        namespace: nil,
        key_config: {none: true},
        use_schema_classes: Deimos.config.schema.use_schema_classes
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
      def _deimos_setup_transcoders
        payload = Transcoder.new(
            schema: schema,
            namespace: namespace,
            use_schema_classes: use_schema_classes,
            topic: name
          )

        key = nil

        if key_config[:plain]
          key = Transcoder.new(
            schema: schema,
            namespace: namespace,
            use_schema_classes: use_schema_classes,
            topic: name
          )
          key.backend = Deimos::SchemaBackends::Plain.new(schema: nil, namespace: nil)
        elsif !key_config[:none]
          if key_config[:field]
            key = Transcoder.new(
              schema: schema,
              namespace: namespace,
              use_schema_classes: use_schema_classes,
              key_field: key_config[:field].to_s,
              topic: name
            )
          elsif key_config[:schema]
            key = Transcoder.new(
              schema: key_config[:schema] || schema,
              namespace: namespace,
              use_schema_classes: use_schema_classes,
              topic: self.name
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
