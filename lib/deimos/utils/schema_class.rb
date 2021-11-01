# frozen_string_literal: true

module Deimos
  module Utils
    # Class used by SchemaClassGenerator and Consumer/Producer interfaces
    module SchemaClass
      class << self
        # Converts a raw payload into an instance of the Schema Class
        # @param payload [Hash]
        # @param schema [String]
        # @return [Deimos::SchemaClass::Record]
        def schema_class_instance(payload, schema)
          klass = "Deimos::#{schema.underscore.camelize}".safe_constantize
          return payload if klass.nil? || payload.nil?

          klass.new(**payload.symbolize_keys)
        end

        # @param config [Hash] Producer or Consumer config
        # @return [Boolean]
        def use_schema_classes?(config)
          use_schema_classes = config[:use_schema_classes]
          use_schema_classes.present? ? use_schema_classes : Deimos.config.schema.use_schema_classes
        end

      end
    end
  end
end
