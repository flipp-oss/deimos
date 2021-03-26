# frozen_string_literal: true

require 'rails/generators'
require 'rails/version'
require 'deimos/utils/schema_model_mixin'

module Deimos
  module Generators
    class SchemaModelGenerator < Rails::Generators::Base
      include Deimos::Utils::SchemaModelMixin

      source_root File.expand_path('schema_model/templates', __dir__)

      argument :full_schema, desc: 'The fully qualified schema name.', required: false

      no_commands do

        # @param file_prefix [String] the name of the generated file, prepended to '_schema.rb'.
        def generate_class(file_prefix)
          template('schema.rb',
                   "app/lib/schema_models/#{namespace_path(@current_schema)}/#{file_prefix}_schema.rb")
          # for every record class, generate a new schema.
          fields.each { |field| generate_record_class(field) if field.type.type == 'record' }
          fields.each { |field| generate_enum_class(field) if field.enum_values.any? }
        end

        # @param record [Object] a field of type 'record'.
        def generate_record_class(record)
          # don't change @current_schema.
          @current_record = record.type
          generate_class(record_filename(@current_schema, record))
          @current_record = nil
        end

        # @param enum [Object] a field of type 'enum'.
        def generate_enum_class(enum)
          @current_enum = enum
          file_prefix = enum_filename(@current_schema, enum)
          template('schema_enum.rb',
                   "app/lib/schema_models/#{namespace_path(@current_schema)}/#{file_prefix}_enum.rb")
          @current_enum = nil
        end

        # @param union [Deimos::SchemaField]
        # @return [String]
        def parse_union(union)
          Avro::Schema::PrimitiveSchema
          types = union.type.schemas.map do |t|
            field_type(Deimos::SchemaField.new('n/a', t))
          end
          types.join(', ')
        end

        ### START Used in template file ###

        # @return [Array<SchemaField>]
        def fields
          if @current_record.nil?
            schema_base.schema_fields
          else
            @current_record.fields.map { |field| Deimos::SchemaField.new(field.name, field.type) }
          end
        end

        # @param schema_field [Deimos::SchemaField]
        # @return [String] a string to use in the YARD doc for the field.
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
            # TODO
            t = parse_union(schema_field)
          elsif t == 'null'
            t = 'nil'
          end
          t
        end

        ### END Used in template file ###

        # @return [Array<String>] array of the full path to each schema in schema.path.
        def find_schemas
          @schemas = Dir["#{Deimos.config.schema.path}/**/*.avsc"]
        end

        # @param s [String] the current schema.
        # @return [String]
        def namespace_path(s)
          namespace(s).gsub('.', '/')
        end

        # @return [Deimos::SchemaBackends::Base]
        def schema_base
          Deimos.schema_backend_class.new(schema: schema(@current_schema), namespace: namespace(@current_schema))
        end

        ### For the Enum Generator ###

        # @param s [String] the current schema.
        # @param enum [Object] a field of type 'enum'.
        # @return [String] the name of the current schema enum, as a class.
        def classified_enum(s, enum)
          "#{schema(s).gsub('-', '_').classify}#{enum.name.gsub('-', '_').classify}Enum"
        end

        # @param enum [Object] a field of type 'enum'.
        # @return [Array<String>] of symbols valid for the enum.
        def enum_symbols(enum)
          enum.enum_values
        end

        def enum_return_values(enum)
          "'#{enum.enum_values.join("', '")}'"
        end

      end

      desc 'Generate a class based on an existing schema.'
      # :nodoc:
      def generate
        if full_schema.nil?  # do all schemas
          find_schemas
          @schemas.each do |s|
            @full_schema_path = s
            schema = File.basename(@full_schema_path, '.avsc')
            namespace_dir = File.dirname(@full_schema_path)
            namespace_dir.slice!(Deimos.config.schema.path + '/')
            namespace_dir = namespace_dir.gsub('/', '.')
            @current_schema = namespace_dir + '.' + schema
            generate_class("#{schema(@current_schema).underscore}")
          end
        else  # do just the specified schema
          @current_schema = full_schema
          generate_class("#{schema(@current_schema).underscore}")
        end
      end

    end
  end
end
