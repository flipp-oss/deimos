module Deimos
  module Utils
    # Mixin to automatically decode schema-encoded payloads when given the correct content type,
    # and provide the `render_schema` method to encode the payload for responses.
    module SchemaControllerMixin
      extend ActiveSupport::Concern

      included do
        Mime::Type.register('avro/binary', :avro)

        attr_accessor :payload
        if respond_to?(:before_filter)
          before_filter :decode_schema, if: :schema_format?
        else
          before_action :decode_schema, if: :schema_format?
        end
      end

      module ClassMethods

        # @return [Hash<Symbol, Hash<Symbol, String>>]
        def schema_mapping
          @schema_mapping ||= {}
        end

        # Indicate which schemas should be assigned to actions.
        # @param actions [Symbol]
        # @param request [String]
        # @param response [String]
        def schemas(*actions, request: nil, response: nil)
          actions.each do |action|
            request ||= action.to_s.titleize
            response ||= action.to_s.titleize
            schema_mapping[action.to_s] = { request: request, response: response}
          end
        end

        # @return [Hash<Symbol, String>]
        def namespaces
          @namespaces ||= {}
        end

        # Set the namespace for both requests and responses.
        # @param ns [String]
        def namespace(ns)
          request_namespace(ns)
          response_namespace(ns)
        end

        # Set the namespace for requests.
        # @param ns [String]
        def request_namespace(ns)
          namespaces[:request] = ns
        end

        # Set the namespace for repsonses.
        # @param ns [String]
        def response_namespace(ns)
          namespaces[:response] = ns
        end
      end

      # @return [Boolean]
      def schema_format?
        request.content_type == Deimos.schema_backend_class.content_type
      end

      # Get the namespace from either an existing instance variable, or tease it out of the schema.
      # @param type [Symbol] :request or :response
      # @return [Array<String, String>] the namespace and schema.
      def parse_namespace(type)
        namespace = self.class.namespaces[type]
        schema = self.class.schema_mapping[params['action']][type]
        if schema.nil?
          raise "No #{type} schema defined for #{params[:controller]}##{params[:action]}!"
        end
        if namespace.nil?
          last_period = schema.rindex('.')
          namespace, schema = schema.split(last_period)
        end
        if namespace.nil? || schema.nil?
          raise "No request namespace defined for #{params[:controller]}##{params[:action]}!"
        end
        [namespace, schema]
      end

      # Decode the payload with the parameters.
      def decode_schema
        namespace, schema = parse_namespace(:request)
        decoder = Deimos.schema_backend(schema: schema, namespace: namespace)
        @payload = decoder.decode(request.body.read).with_indifferent_access
        request.body.rewind if request.body.respond_to?(:rewind)
      end

      # Render a hash into a payload as specified by the configured schema and namespace.
      # @param payload [Hash]
      def render_schema(payload, schema: nil, namespace: nil)
        namespace, schema = parse_namespace(:response) if !schema && !namespace
        encoder = Deimos.schema_backend(schema: schema, namespace: namespace)
        encoded = encoder.encode(payload)
        response.headers['Content-Type'] = encoder.class.content_type
        send_data(encoded)
      end
    end
  end
end
