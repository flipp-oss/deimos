# frozen_string_literal: true

module Deimos
  module Utils
    # Class used by SchemaClassGenerator and Consumer/Producer interfaces
    module SchemaClass
      class << self
        # Converts a raw payload into an instance of the Schema Class
        # @param payload [Hash, Deimos::SchemaClass::Base]
        # @param schema [String]
        # @return [Deimos::SchemaClass::Record]
        def instance(payload, schema)
          return payload if payload.is_a?(Deimos::SchemaClass::Base)

          klass = "Schemas::#{schema.underscore.camelize}".safe_constantize
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
