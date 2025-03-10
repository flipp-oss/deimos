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
          namespace_override = nil
          module_namespace = namespace

          if Deimos.config.schema.use_full_namespace
            if Deimos.config.schema.schema_namespace_map.present?
              namespace_keys = Deimos.config.schema.schema_namespace_map.keys.sort_by { |k| -k.length }
              namespace_override = namespace_keys.find { |k| module_namespace.include?(k) }
            end

            if namespace_override.present?
              # override default module
              modules = Array(Deimos.config.schema.schema_namespace_map[namespace_override])
              module_namespace = module_namespace.gsub(/#{namespace_override}\.?/, '')
            end

            namespace_folders = module_namespace.split('.').map { |f| f.underscore.camelize }
            modules.concat(namespace_folders) if namespace_folders.any?
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

          klass = klass(schema, namespace)
          return payload if klass.nil? || payload.nil?

          klass.new(**payload.symbolize_keys)
        end

        # Determine and return the SchemaClass with the provided schema and namespace
        # @param schema [String]
        # @param namespace [String]
        # @return [Deimos::SchemaClass]
        def klass(schema, namespace)
          constants = modules_for(namespace) + [schema.underscore.camelize.singularize]
          constants.join('::').safe_constantize
        end

        # @param config [Hash] Producer or Consumer config
        # @return [Boolean]
        def use?(config)
          config.has_key?(:use_schema_classes) ? config[:use_schema_classes] : Deimos.config.schema.use_schema_classes
        end

      end
    end
  end
end
