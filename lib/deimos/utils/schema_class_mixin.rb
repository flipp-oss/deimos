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
      # @return [Deimos::SchemaRecord]
      def schema_class_record(payload, schema)
        klass = classified_schema(schema)
        return payload if klass.nil?

        klass.initialize_from_payload(payload)
      end

      # @param config [FigTree::ConfigStruct] Producer or Consumer config
      # @return [Boolean]
      def use_schema_classes?(config)
        use_schema_classes = config[:use_schema_classes]
        use_schema_classes.present? ? use_schema_classes : Deimos.config.schema.use_schema_classes
      end
    end
  end
end
