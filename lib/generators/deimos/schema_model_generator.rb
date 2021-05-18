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
               desc: 'The fully qualified schema name.',
               required: false,
               type: :string

      no_commands do
        # Retrieve the fields from this Avro Schema
        # @return [Array<SchemaField>]
        def fields
          if @current_record.nil?
            schema_base.schema_fields
          else
            @current_record.fields.map { |field| Deimos::SchemaField.new(field.name, field.type) }
          end
        end

        # Load the schema from the Schema Backend
        # @return [Deimos::SchemaBackends::Base]
        def schema_base
          Deimos.schema_backend_class.new(schema: schema(@current_schema), namespace: namespace(@current_schema))
        end

        # Converts Deimos::SchemaField's to String form for generated YARD docs
        # @param schema_field [Deimos::SchemaField]
        # @return [String] A string representation of the Type of this SchemaField
        def field_type(schema_field)
          t = schema_field.type.type
          if %w(string boolean).include?(t)
            t = t.titleize
          elsif %w(int long).include?(t)
            t = 'Integer'
          elsif %w(float double).include?(t)
            t = 'Float'
          elsif t == 'record'
            t = "Deimos::#{record_classname(@current_schema, schema_field.type)}"
          elsif t == 'array'
            arr_t = field_type(Deimos::SchemaField.new('n/a', schema_field.type.items))
            t = "Array<#{arr_t}>"
          elsif t == 'map'
            map_t = field_type(Deimos::SchemaField.new('n/a', schema_field.type.values))
            t = "Hash<String, #{map_t}>"
          elsif t == 'enum'
            t = "Deimos::#{enum_classname(@current_schema, schema_field)}"
          elsif t == 'union'
            # TODO Check or add specs for this
            t = parse_union(schema_field)
          elsif t == 'null'
            t = 'nil'
          end
          t
        end

        # TODO: Looks like this is not completed yet? Might have to do some extra work here.
        # TODO: Potentially do Union of null with Record, doesn't look like that is covered as of yet?
        # Parse a Union of two or more Deimos::SchemaField's
        # @param union [Deimos::SchemaField]
        # @return [String]
        def parse_union(union)
          # What does this do..? Can remove i guess...?
          Avro::Schema::PrimitiveSchema
          types = union.type.schemas.map do |t|
            field_type(Deimos::SchemaField.new('n/a', t))
          end
          types.join(', ')
        end

        # Generate a Schema Model Class and all of its Nested Records from an Avro Schema
        # @param file_prefix [String] the name of the generated file, prepended to '_schema.rb'.
        def generate_class(file_prefix)
          template('schema.rb',
                   "#{GENERATED_PATH}/#{namespace_path(@current_schema)}/#{file_prefix}.rb",
                   force: true)

          # for every Nested record or Complex class, generate a new schema.
          # TODO: Are Unions handled here?
          fields.each do |field|
            generate_record_class(field) if field.type.type == 'record'
            generate_enum_class(field) if field.enum_values.any?
          end
        end

        # Generate a Record Schema Class from Avro Schema
        # @param record [Object] a field of type 'record'.
        def generate_record_class(record)
          # don't change @current_schema.
          @current_record = record.type
          generate_class(record_filename(@current_schema, record))
          @current_record = nil
        end

        # Generate an Enum Schema Class from Avro Schema
        # @param enum [Object] a field of type 'enum'.
        def generate_enum_class(enum)
          @current_enum = enum
          file_prefix = enum_filename(@current_schema, enum)
          template('schema_enum.rb',
                   "#{GENERATED_PATH}/#{namespace_path(@current_schema)}/#{file_prefix}.rb",
                   force: true)
          @current_enum = nil
        end

        # @param schema [String] the current schema.
        # @return [String]
        def namespace_path(schema)
          namespace(schema).gsub('.', '/')
        end

        # @param enum [Object] a field of type 'enum'.
        # @return [Array<String>] of symbols valid for the enum.
        def enum_symbols(enum)
          enum.enum_values
        end

        # @param enum [Object] a field of type 'enum'.
        # @return [String] the possible return values for this Enum type
        def enum_return_values(enum)
          "'#{enum.enum_values.join("', '")}'"
        end

      end

      desc 'Generate a class based on an existing schema.'
      def generate
        Rails.logger.info(Deimos.config.schema.path)
        if full_schema.nil?  # do all schemas
          _find_schemas
          @schemas.each do |schema|
            full_schema_path = schema
            @current_schema = _parse_schema(schema)
            generate_class("#{schema(@current_schema).underscore}")
          end
        else  # do just the specified schema
          @current_schema = _parse_schema(full_schema)
          generate_class("#{schema(@current_schema).underscore}")
        end
      end

      private

      # Retrieve all Avro Schemas under the configured Schema path
      # @return [Array<String>] array of the full path to each schema in schema.path.
      def _find_schemas
        @schemas = Dir["#{_schema_path}/**/*.avsc"]
      end

      def _schema_path
        Deimos.config.schema.path || File.expand_path('app/schemas', __dir__)
      end

      # This function is important. Must handle different cases for File/Schema names
      # "Schema" given from GuardFile is -> in the format of "com/flipp/test_rails_service/MySchema"
      def _parse_schema(schema)
        return schema unless schema =~ /\//

        full_schema_path = File.absolute_path(schema)
        schema_name = File.basename(full_schema_path, '.avsc')
        namespace_dir = File.dirname(full_schema_path)
        namespace_dir.slice!("#{_schema_path}/")
        namespace_dir = namespace_dir.gsub('/', '.')
        "#{namespace_dir}.#{schema_name}"
      end

      def _setup_guardfile
        Rails.logger.info('Setting up Guardfile')
      end

    end
  end
end
