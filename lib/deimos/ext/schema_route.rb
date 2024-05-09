require "deimos/transcoder"
require "deimos/ext/producer_middleware"
require "deimos/schema_backends/plain"

module Deimos
  class SchemaRoute < Karafka::Routing::Features::Base

    def self.activate
      Deimos::ProducerMiddleware.producer_configs ||= {}
      super
    end

    module Topic
      def schema(schema:, namespace: nil, key_config: {}, use_schema_classes: false)
        transcoders = {
          payload: Transcoder.new(
            schema: schema,
            namespace: namespace,
            use_schema_classes: use_schema_classes,
            topic: self.name
          )
        }

        if key_config[:plain]
          transcoders[:key] = Transcoder.new(
            schema: schema,
            namespace: namespace,
            use_schema_classes: use_schema_classes,
            topic: self.name
          )
          transcoders[:key].backend = Deimos::SchemaBackends::Plain.new(schema: nil, namespace: nil)
        elsif !key_config[:none]
          if key_config[:field]
            transcoders[:key] = Transcoder.new(
              schema: schema,
              namespace: namespace,
              use_schema_classes: use_schema_classes,
              key_field: key_config[:field].to_s,
              topic: self.name
            )
          else
            transcoders[:key] = Transcoder.new(
              schema: key_config[:schema] || schema,
              namespace: namespace,
              use_schema_classes: use_schema_classes,
              topic: self.name
            )
          end
        end
        Deimos::ProducerMiddleware.producer_configs[self.name] = Deimos::ProducerConfig.new(
          self,
          transcoders
        )
        deserializers(**transcoders)

      end
    end
  end
end

Deimos::SchemaRoute.activate
