# frozen_string_literal: true

module Deimos
  module Utils
    # Module with Quality of Life methods used in SchemaClassGenerator and Consumer/Producer interfaces
    module SchemaClassMixin

      # @param schema [String] the current schema name as a string
      # @return [Class] the Class of the current schema.
      def classified_schema(schema)
        "Deimos::#{schema.underscore.camelize}".safe_constantize
      end

      # Converts a raw payload into an instance of the Schema Class
      # @param payload [Hash]
      # @param schema [String]
      # @return [Deimos::SchemaClass::Record]
      def schema_class_instance(payload, schema)
        klass = classified_schema(schema)
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
