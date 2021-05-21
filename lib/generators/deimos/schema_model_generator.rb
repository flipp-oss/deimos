# frozen_string_literal: true

require 'rails/generators'
require 'deimos'
require 'deimos/utils/schema_model_mixin'
require 'deimos/config/configuration'

module Deimos
  module Generators
    class SchemaModelGenerator < Rails::Generators::Base
      include Deimos::Utils::SchemaModelMixin

      GENERATED_PATH = "app/lib/schema_models".freeze

      source_root File.expand_path('schema_model/templates', __dir__)

      argument :full_schema,
               desc: 'The fully qualified schema name or path.',
               required: false,
               type: :string

      no_commands do

        # Load the schema from the Schema Backend
        # @param schema [String] the Schemas name
        # @return [Deimos::SchemaBackends::Base]
        def schema_base(schema=nil)
          @schema_base ||= Deimos.schema_backend_class.new(schema: extract_schema(schema), namespace: extract_namespace(schema))
        end

        # Unload the schema
        def clear_schema_base!
          @schema_base = nil
        end

        # Generate a Schema Model Class and all of its Nested Records from an Avro Schema
        # @param schema_name [String] the name of the Avro Schema in Dot Syntax
        def generate_classes_from_schema(schema_name)
          schema_base(schema_name).load_schema!
          schema_base.schema_store.schemas.values.each do |schema|
            @current_schema = schema
            file_prefix = schema.name.underscore
            namespace_path = schema.namespace.tr('.', '/')
            schema_template = "schema_#{schema.type}.rb"
            filename = "#{GENERATED_PATH}/#{namespace_path}/#{file_prefix}.rb"
            template(schema_template, filename, force: true)
          end
          clear_schema_base!
        end

        # Retrieve the fields from this Avro Schema
        # @return [Array<SchemaField>]
        def fields
          @current_schema.fields.map { |field| Deimos::SchemaField.new(field.name, field.type) }
        end

        # Converts Deimos::SchemaField's to String form for generated YARD docs
        # @param schema_field [Deimos::SchemaField]
        # @return [String] A string representation of the Type of this SchemaField
        def field_type(schema_field)
          field_type = schema_field.type.type.to_sym

          case field_type
          when :string, :boolean
            field_type.to_s.titleize
          when :int, :long
            'Integer'
          when :float, :double
            'Float'
          when :record, :enum
            "Deimos::#{schema_classname(schema_field.type)}"
          when :array
            arr_t = field_type(Deimos::SchemaField.new('n/a', schema_field.type.items))
            "Array<#{arr_t}>"
          when :map
            map_t = field_type(Deimos::SchemaField.new('n/a', schema_field.type.values))
            "Hash<String, #{map_t}>"
          when :union
            types = schema_field.type.schemas.map do |t|
              field_type(Deimos::SchemaField.new('n/a', t))
            end
            types.join(', ')
          when :null
            'nil'
          end
        end

        # @param enum [Avro::Schema::EnumSchema] a field of type 'enum'.
        # @return [Array<String>] of symbols valid for the enum.
        def enum_symbols(enum)
          enum.symbols
        end

        # @param enum [Avro::Schema::EnumSchema] a field of type 'enum'.
        # @return [String] the possible return values for this Enum type
        def enum_return_values(enum)
          "'#{enum.symbols.join("', '")}'"
        end

      end

      desc 'Generate a class based on an existing schema.'
      def generate
        Rails.logger.info(Deimos.config.schema.path)
        if full_schema.nil?  # do all schemas
          _find_schema_paths.each do |schema_path|
            current_schema = _parse_schema_from_path(schema_path)

            generate_classes_from_schema(current_schema)
          end
        else
          current_schema = _parse_schema_from_path(full_schema)
          generate_classes_from_schema(current_schema)
        end
      end

      private

      # Retrieve all Avro Schemas under the configured Schema path
      # @return [Array<String>] array of the full path to each schema in schema.path.
      def _find_schema_paths
        Dir["#{_schema_path}/**/*.avsc"]
      end

      def _schema_path
        Deimos.config.schema.path || File.expand_path('app/schemas', __dir__)
      end

      # Parses the schema in dot syntax from a given Schema Path.
      # Handles different cases for File/Schema names.
      # @return [String] The name of the schema in the format of com.my.namespace.MySchema
      def _parse_schema_from_path(schema_path)
        return schema_path unless schema_path =~ /\//

        full_schema_path = File.absolute_path(schema_path)
        schema_name = File.basename(full_schema_path, '.avsc')
        namespace_dir = File.dirname(full_schema_path).
          delete_prefix("#{_schema_path}/").
          gsub('/', '.')

        "#{namespace_dir}.#{schema_name}"
      end

    end
  end
end
