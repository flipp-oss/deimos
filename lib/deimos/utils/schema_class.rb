# frozen_string_literal: true

module Deimos
  module Utils
    # Class used by SchemaClassGenerator and Consumer/Producer interfaces
    module SchemaClass
      class << self

        # @param namespace [String]
        # @return [Array<String>]
        def modules_for(namespace)
          modules = ['Schemas']
          namespace_folder = namespace.split('.').last
          if Deimos.config.schema.generate_namespace_folders && namespace_folder
            modules.push(namespace_folder.underscore.classify)
          end
          modules
        end

        # Converts a raw payload into an instance of the Schema Class
        # @param payload [Hash, Deimos::SchemaClass::Base]
        # @param schema [String]
        # @param namespace [String]
        # @return [Deimos::SchemaClass::Record]
        def instance(payload, schema, namespace='')
          return payload if payload.is_a?(Deimos::SchemaClass::Base)

          constants = modules_for(namespace) + [schema.underscore.camelize.singularize]
          klass = constants.join('::').safe_constantize
          return payload if klass.nil? || payload.nil?

          klass.new(**payload.symbolize_keys)
        end

        # @param config [Hash] Producer or Consumer config
        # @return [Boolean]
        def use?(config)
          use_schema_classes = config[:use_schema_classes]
          use_schema_classes.present? ? use_schema_classes : Deimos.config.schema.use_schema_classes
        end
      end
    end
  end
end
