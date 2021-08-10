# frozen_string_literal: true

require 'rails/generators'
require 'deimos'
require 'deimos/utils/schema_class_mixin'
require 'deimos/config/configuration'

# Generates new schema classes.
module Deimos
  module Generators
    # Generator for Schema Classes used for the IDE and consumer/producer interfaces
    class SchemaClassGenerator < Rails::Generators::Base
      include Deimos::Utils::SchemaClassMixin

      SPECIAL_TYPES = %i(record enum).freeze

      source_root File.expand_path('schema_class/templates', __dir__)

      argument :full_schema,
               desc: 'The fully qualified schema name or path.',
               required: false,
               type: :string

      no_commands do

        # Load the schema from the Schema Backend
        # @param schema [String] the Schemas name
        # @return [Deimos::SchemaBackends::Base]
        def schema_base(schema=nil)
          @schema_base ||= Deimos.schema_backend_class.new(schema: extract_schema(schema),
                                                           namespace: extract_namespace(schema))
        end

        # Unload the schema
        def clear_schema_base!
          @schema_base = nil
        end

        # Generate a Schema Model Class and all of its Nested Records from an Avro Schema
        # @param schema_name [String] the name of the Avro Schema in Dot Syntax
        def generate_classes_from_schema(schema_name)
          schema_base(schema_name).load_schema!
          schema_base.schema_store.schemas.each_value do |schema|
            @current_schema = schema
            @special_field_initialization = schema.type_sym == :record ? special_field_initialization : {}
            file_prefix = schema.name.underscore
            namespace_path = schema.namespace.tr('.', '/')
            schema_template = "schema_#{schema.type}.rb"
            filename = "#{Deimos.config.schema.generated_class_path}/#{namespace_path}/#{file_prefix}.rb"
            template(schema_template, filename, force: true)
          end
          clear_schema_base!
        end

        # Retrieve the fields from this Avro Schema
        # @return [Array<SchemaField>]
        def fields
          @current_schema.fields.map { |field| Deimos::SchemaField.new(field.name, field.type) }
        end

        # @param avro_schema [Avro::Schema::NamedSchema]
        # @return [Symbol]
        def schema_base_type(avro_schema)
          case avro_schema.type_sym
          when :array
            schema_base_type(avro_schema.items)
          when :map
            schema_base_type(avro_schema.values)
          when :union
            avro_schema.schemas.map(&method(:schema_base_type)).
              reject { |schema| schema.type_sym == :null }.first
          else
            avro_schema
          end
        end

        # Retrieve any special formatting needed for this current schema's fields
        # @return [Hash<String, Array[Symbol]>]
        def special_field_initialization
          result = Hash.new { |h, k| h[k] = [] }
          fields.each do |field|
            field_base_type = field.type.type_sym # Record, Union, Enum, Array or Map?
            sub_type_schema = schema_base_type(field.type)
            initialize_method = field_initialize_formatting(sub_type_schema)

            next unless initialize_method.present?

            initialize_string = case field_base_type
                                when :array
                                  "value.map { |v| #{initialize_method}(v) }"
                                when :map
                                  "value.transform_values { |v| #{initialize_method}(v) }"
                                else
                                  "#{initialize_method}(value)"
                                end

            result[initialize_string] << ":#{field.name}"
          end
          result
        end

        # @param avro_schema [Avro::Schema::NamedSchema]
        # @return [String]
        def field_initialize_formatting(avro_schema)
          field_type = field_type(avro_schema)
          case avro_schema.type_sym
          when :record
            "#{field_type}.initialize_from_payload"
          when :enum
            "#{field_type}.new"
          else
            nil
          end
        end

        # Format a given field into it's appropriate to_h representation.
        # @param field[Deimos::SchemaField]
        # @return [String]
        def field_to_h_formatting(field)
          res = "'#{field.name}' => @#{field.name}"
          field_base_type = schema_base_type(field.type).type_sym

          if %i(record enum).include?(field_base_type)
            res += case field.type.type_sym
                    when :array
                      ".map { |v| v&.to_h }"
                    when :map
                      ".transform_values { |v| v&.to_h }"
                    else
                      "&.to_h"
                    end
          end

          res + (field.name == fields.last.name ? '' : ',')
        end

        # Converts Avro::Schema::NamedSchema's to String form for generated YARD docs.
        # Recursively handles the typing for Arrays, Maps and Unions.
        # @param avro_schema [Avro::Schema::NamedSchema]
        # @return [String] A string representation of the Type of this SchemaField
        def field_type(avro_schema)
          case avro_schema.type_sym
          when :string, :boolean
            avro_schema.type_sym.to_s.titleize
          when :int, :long
            'Integer'
          when :float, :double
            'Float'
          when :record, :enum
            "Deimos::#{schema_classname(avro_schema)}"
          when :array
            arr_t = deimos_field_type(Deimos::SchemaField.new('n/a', avro_schema.items))
            "Array<#{arr_t}>"
          when :map
            map_t = deimos_field_type(Deimos::SchemaField.new('n/a', avro_schema.values))
            "Hash<String, #{map_t}>"
          when :union
            types = avro_schema.schemas.map do |t|
              deimos_field_type(Deimos::SchemaField.new('n/a', t))
            end
            types.join(', ')
          when :null
            'nil'
          end
        end

        # Converts Deimos::SchemaField's to String form for generated YARD docs
        # @param schema_field [Deimos::SchemaField]
        # @return [String] A string representation of the Type of this SchemaField
        def deimos_field_type(schema_field)
          field_type(schema_field.type)
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
      # :nodoc:
      def generate
        Rails.logger.info(Deimos.config.schema.path)
        if full_schema.nil?
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
        return schema_path unless schema_path =~ %r{/}

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
