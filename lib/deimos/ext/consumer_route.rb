module Deimos
  class SchemaRoute < Karafka::Routing::Features::Base
    module Topic
      def schema(schema:, namespace: nil, key_config: {}, use_schema_classes: false)
        decoders = {
          payload: Decoder.new(
            schema: schema,
            namespace: namespace,
            use_schema_classes: use_schema_classes
          )
        }

        if !key_config[:plain] && !key_config[:none]
          if key_config[:field]
            decoders[:key] = Decoder.new(
              schema: schema,
              namespace: namespace,
              use_schema_classes: use_schema_classes,
              key_field: key_config[:field].to_s
            )
          else
            decoders[:key] = Decoder.new(
              schema: key_config[:schema] || schema,
              namespace: namespace,
              use_schema_classes: use_schema_classes,
            )
          end
        end
        deserializers(**decoders)

      end
    end
  end
end

Deimos::SchemaRoute.activate
