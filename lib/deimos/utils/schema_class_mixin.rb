# frozen_string_literal: true

module Deimos
  module Utils
    # Module with Quality of Life methods used in SchemaClassGenerator and Consumer/Producer interfaces
    module SchemaClassMixin

      # @param schema [String] the current schema.
      # @return [String] the schema name, without its namespace.
      def extract_schema(schema)
        last_dot = schema.rindex('.')
        schema[last_dot + 1..-1] || 'ERROR'
      end

      # @param schema [String] the current schema.
      # @return [String] the schema namespace, without its name.
      def extract_namespace(schema)
        last_dot = schema.rindex('.')
        schema[0...last_dot] || 'ERROR'
      end

      # @param schema [String] the current schema name as a string
      # @return [String] the name of the current schema, as a class.
      def classified_schema(schema)
        "#{schema.underscore.camelize}"
      end

      # @param schema [Avro::Schema::NamedSchema] A named schema
      # @return [String]
      def schema_classname(schema)
        "#{schema.name.underscore.camelize}"
      end

    end
  end
end
