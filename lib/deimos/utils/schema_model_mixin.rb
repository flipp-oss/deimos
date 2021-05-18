# frozen_string_literal: true

module Deimos
  module Utils
    # Module with Quality of Life methods used in SchemaModelGenerator and Consumer/Producer interfaces
    module SchemaModelMixin

      # @param schema [String] the current schema.
      # @return [String] the schema name, no namespace.
      def schema(schema)
        last_dot = schema.rindex('.')
        schema[last_dot + 1..-1] || 'ERROR'
      end

      # @param schema [String] the current schema.
      # @return [String] the schema namespace, without its name.
      def namespace(schema)
        last_dot = schema.rindex('.')
        schema[0...last_dot] || 'ERROR'
      end

      # @param schema [String] the current schema.
      # @param record [Object] a field of type 'record'.
      # @return [String] the name of the current schema, as a class.
      def classified_schema(schema, record)
        if record.nil?
          "#{schema(schema).gsub('-', '_').classify}"
        else
          record_classname(schema, record)
        end
      end

      # @param schema [String] the current schema.
      # @param record [Object] a field of type 'record'.
      # @return [String]
      def record_filename(schema, record)
        "#{schema(schema).underscore}_#{record.type.name.underscore}"
      end

      # @param schema [String] the current schema.
      # @param record [Object] a field of type 'record'.
      # @return [String]
      def record_classname(schema, record)
        "#{schema(schema).gsub('-', '_').classify}#{record.name.gsub('-', '_').classify}"
      end

      # @param schema [String] the current schema.
      # @param enum [Object] a field of type 'enum'.
      # @return [String] the name of the current schema enum, as a class.
      def classified_enum(schema, enum)
        "#{schema(schema).gsub('-', '_').classify}#{enum.name.gsub('-', '_').classify}"
      end

      # @param schema [String] the current schema.
      # @param enum [Object] a field of type 'enum'.
      # @return [String]
      def enum_filename(schema, enum)
        "#{schema(schema).underscore}_#{enum.type.name.underscore}"
      end

      # @param schema [String] the current schema.
      # @param enum [Object] a field of type 'enum'.
      # @return [String]
      def enum_classname(schema, enum)
        "#{schema(schema).gsub('-', '_').classify}#{enum.type.name.gsub('-', '_').classify}"
      end

    end
  end
end
