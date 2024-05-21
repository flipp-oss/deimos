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
        use_schema_classes: nil
      }.each do |field, default|
        define_method(field) do |val=Karafka::Routing::Default.new(nil)|
          @_deimos_config ||= {}
          @_deimos_config[:schema] ||= {}
          unless val.is_a?(Karafka::Routing::Default)
            @_deimos_config[:schema][field] = val
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
          else
            key = Transcoder.new(
              schema: key_config[:schema] || schema,
              namespace: namespace,
              use_schema_classes: use_schema_classes,
              topic: self.name
            )
          end
        end
        deserializers.payload = payload
        deserializers.key = key if key
      end
    end
  end
end

Deimos::SchemaRoute.activate
