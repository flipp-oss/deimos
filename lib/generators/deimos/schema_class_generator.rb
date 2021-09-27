# frozen_string_literal: true

require 'rails/generators'
require 'deimos'
require 'deimos/utils/schema_class_mixin'
require 'deimos/schema_backends/avro_base'
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
        # Retrieve the fields from this Avro Schema
        # @return [Array<SchemaField>]
        def fields
          @current_schema.fields.map { |field| Deimos::SchemaField.new(field.name, field.type) }
        end

        # Converts Deimos::SchemaField's to String form for generated YARD docs
        # @param schema_field [Deimos::SchemaField]
        # @return [String] A string representation of the Type of this SchemaField
        def deimos_field_type(schema_field)
          _field_type(schema_field.type)
        end

        # @param schema [Avro::Schema::NamedSchema] A named schema
        # @return [String]
        def schema_classname(schema)
          schema.name.underscore.camelize
        end

        # Generate a Schema Model Class and all of its Nested Records from an Avro Schema
        # @param schema_name [String] the name of the Avro Schema in Dot Syntax
        def generate_classes_from_schema(schema_name)
          schema_base = _schema_base(schema_name)
          schema_base.load_schema
          schema_base.schema_store.schemas.each_value do |schema|
            @current_schema = schema
            @schema_is_key = schema_base.is_key_schema?
            @initialization_definition = _initialization_definition if schema.type_sym == :record
            @special_field_initialization = schema.type_sym == :record ? _special_field_initialization : {}
            @field_assignment_overrides = schema.type_sym == :record ? _field_assignment_overrides : {}
            file_prefix = schema.name.underscore
            namespace_path = schema.namespace.tr('.', '/')
            schema_template = "schema_#{schema.type}.rb"
            filename = "#{Deimos.config.schema.generated_class_path}/#{namespace_path}/#{file_prefix}.rb"
            template(schema_template, filename, force: true)
          end
        end

        # Format a given field into its appropriate to_h representation.
        # @param field[Deimos::SchemaField]
        # @return [String]
        def field_to_h(field)
          res = "'#{field.name}' => @#{field.name}"
          field_base_type = _schema_base_type(field.type).type_sym

          if %i(record enum).include?(field_base_type)
            res += case field.type.type_sym
                   when :array
                     '.map { |v| v&.to_h }'
                   when :map
                     '.transform_values { |v| v&.to_h }'
                   else
                     '&.to_h'
                   end
          end

          res + (field.name == fields.last.name ? '' : ',')
        end

      end

      desc 'Generate a class based on existing schema(s).'
      # :nodoc:
      def generate
        _validate
        Rails.logger.info("Generating schemas from #{Deimos.config.schema.path}")
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

      # TODO - Allow for overriding or extension of this generator for other Schema Backends
      # Determines if Schema Class Generation can be run.
      # @raise if Schema Backend is not of a Avro-based class
      def _validate
        backend = Deimos.config.schema.backend.to_s
        raise 'Schema Class Generation requires an Avro-based Schema Backend' if backend !~ /^avro/
      end

      # Retrieve all Avro Schemas under the configured Schema path
      # @return [Array<String>] array of the full path to each schema in schema.path.
      def _find_schema_paths
        Dir["#{_schema_path}/**/*.avsc"]
      end

      def _schema_path
        Deimos.config.schema.path || File.expand_path('app/schemas', __dir__)
      end

      # Load the schema from the Schema Backend
      # @param full_schema [String] the Schemas Full name
      # @return [Deimos::SchemaBackends::AvroBase]
      def _schema_base(full_schema=nil)
        schema = Deimos::SchemaBackends::AvroBase.extract_schema(full_schema)
        namespace = Deimos::SchemaBackends::AvroBase.extract_namespace(full_schema)
        Deimos::SchemaBackends::AvroBase.new(schema: schema, namespace: namespace)
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

      # Defines the initialization method for Schema Records. Handles wrapping when the list of
      # arguments is too long.
      # @return [String] A string which defines the method signature for the initialize method
      def _initialization_definition
        arguments = fields.map { |v| "#{v.name}:"}
        arguments += ['payload_key:nil'] unless @schema_is_key
        remaining_arguments = arguments.join(', ')

        wrapped_arguments = []
        char_limit = 80
        until remaining_arguments.length < char_limit
          index_of_last_comma = remaining_arguments.first(char_limit).rindex(/,/)
          wrapped_arguments << remaining_arguments[0..index_of_last_comma] + "\n"
          remaining_arguments = remaining_arguments[(index_of_last_comma+2)..-1]
        end
        wrapped_arguments << remaining_arguments + ')'

        result = "def initialize(#{wrapped_arguments.first}"
        wrapped_arguments[1..-1].each do |args|
          result += "                   #{args}"
        end
        result
      end

      # Overrides default attr accessor methods
      # @return [Array<String>]
      def _field_assignment_overrides
        # TODO: Handle default values here too..!
        result = []
        fields.each do |field|
          field_type = field.type.type_sym # Record, Union, Enum, Array or Map
          schema_base_type = _schema_base_type(field.type)
          field_base_type = _field_type(schema_base_type)

          next unless %i(record enum).include? schema_base_type.type_sym

          value_prefix = schema_base_type.type_sym == :record ? '**' : ''
          field_initialization = "value.present? && !value.is_a?(#{field_base_type}) ? #{field_base_type}.new(#{value_prefix}value) : value"
          method_argument = %i(array map).include?(field_type) ? 'values' : 'value'

          result << {
            field_name: field.name,
            field_type: field_type,
            method_argument: method_argument,
            field_initialization: field_initialization
          }
        end

        result
      end

      # Retrieve any special formatting needed for this current schema's fields
      # @return [Hash<String, Array[Symbol]>]
      def _special_field_initialization
        result = Hash.new { |h, k| h[k] = [] }
        fields.each do |field|
          field_base_type = field.type.type_sym # Record, Union, Enum, Array or Map?
          sub_type_schema = _schema_base_type(field.type)
          initialize_method = _field_initialize_formatting(sub_type_schema)

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

      # Converts Avro::Schema::NamedSchema's to String form for generated YARD docs.
      # Recursively handles the typing for Arrays, Maps and Unions.
      # @param avro_schema [Avro::Schema::NamedSchema]
      # @return [String] A string representation of the Type of this SchemaField
      def _field_type(avro_schema)
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

      # @param avro_schema [Avro::Schema::NamedSchema]
      # @return [Symbol]
      def _schema_base_type(avro_schema)
        case avro_schema.type_sym
        when :array
          _schema_base_type(avro_schema.items)
        when :map
          _schema_base_type(avro_schema.values)
        when :union
          avro_schema.schemas.map(&method(:_schema_base_type)).
            reject { |schema| schema.type_sym == :null }.first
        else
          avro_schema
        end
      end

      # @param avro_schema [Avro::Schema::NamedSchema]
      # @return [String]
      def _field_initialize_formatting(avro_schema)
        field_type = _field_type(avro_schema)
        case avro_schema.type_sym
        when :record
          "#{field_type}.initialize_from_json_payload"
        when :enum
          "#{field_type}.new"
        else
          nil
        end
      end

    end
  end
end
