# frozen_string_literal: true

module Deimos
  module Utils
    # Module with methods used in SchemaModelGenerator but also need elsewhere
    module SchemaModelMixin

      # @param s [String] the current schema.
      # @return [String] the schema name, no namespace.
      def schema(s)
        last_dot = s.rindex('.')
        s[last_dot + 1..-1] || 'ERROR'
      end

      # @param s [String] the current schema.
      # @return [String] the schema namespace, without its name.
      def namespace(s)
        last_dot = s.rindex('.')
        s[0...last_dot] || 'ERROR'
      end

      # @param s [String] the current schema.
      # @param record [Object] a field of type 'record'.
      # @return [String] the name of the current schema, as a class.
      def classified_schema(s, record)
        if record.nil?
          "#{schema(s).gsub('-', '_').classify}Schema"
        else
          record_classname(s, record)
        end
      end

      # @param s [String] the current schema.
      # @param record [Object] a field of type 'record'.
      # @return [String]
      def record_filename(s, record)
        "#{schema(s).underscore}_#{record.type.name.underscore}"
      end

      # @param s [String] the current schema.
      # @param record [Object] a field of type 'record'.
      # @return [String]
      def record_classname(s, record)
        "#{schema(s).gsub('-', '_').classify}#{record.name.gsub('-', '_').classify}Schema"
      end

      # @param s [String] the current schema.
      # @param enum [Object] a field of type 'enum'.
      # @return [String]
      def enum_filename(s, enum)
        "#{schema(s).underscore}_#{enum.type.name.underscore}"
      end

      # @param s [String] the current schema.
      # @param enum [Object] a field of type 'enum'.
      # @return [String]
      def enum_classname(s, enum)
        "#{schema(s).gsub('-', '_').classify}#{enum.type.name.gsub('-', '_').classify}Enum"
      end

    end
  end
end
