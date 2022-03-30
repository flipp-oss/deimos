# frozen_string_literal: true

require 'rails/generators'
require 'deimos'
require 'deimos/schema_backends/avro_base'
require 'deimos/config/configuration'

# Generates new schema classes.
module Deimos
  module Generators
    # Generator for Schema Classes used for the IDE and consumer/producer interfaces
    class SchemaClassGenerator < Rails::Generators::Base

      SPECIAL_TYPES = %i(record enum).freeze
      INITIALIZE_WHITESPACE = "\n#{' ' * 19}"
      IGNORE_DEFAULTS = %w(message_id timestamp).freeze
      SCHEMA_CLASS_FILE = 'schema_class.rb'
      SCHEMA_RECORD_PATH = File.expand_path('schema_class/templates/schema_record.rb.tt', __dir__).freeze
      SCHEMA_ENUM_PATH = File.expand_path('schema_class/templates/schema_enum.rb.tt', __dir__).freeze

      source_root File.expand_path('schema_class/templates', __dir__)

      no_commands do
        # Retrieve the fields from this Avro Schema
        # @param schema [Avro::Schema::NamedSchema]
        # @return [Array<SchemaField>]
        def fields(schema)
          schema.fields.map do |field|
            Deimos::SchemaField.new(field.name, field.type, [], field.default)
          end
        end

        # Converts Deimos::SchemaField's to String form for generated YARD docs
        # @param schema_field [Deimos::SchemaField]
        # @return [String] A string representation of the Type of this SchemaField
        def deimos_field_type(schema_field)
          _field_type(schema_field.type)
        end

        # Generate a Schema Model Class and all of its Nested Records from a
        # Deimos Consumer or Producer Configuration object
        # @param schema_name [String]
        # @param namespace [String]
        # @param key_schema_name [String]
        def generate_classes(schema_name, namespace, key_schema_name)
          schema_base = Deimos.schema_backend(schema: schema_name, namespace: namespace)
          schema_base.load_schema
          if key_schema_name.present?
            key_schema_base = Deimos.schema_backend(schema: key_schema_name, namespace: namespace)
            key_schema_base.load_schema
            generate_class_from_schema_base(key_schema_base)
          end
          generate_class_from_schema_base(schema_base, key_schema_base: key_schema_base)
        end

        # @param schema [Avro::Schema::NamedSchema]
        # @return [Array<Avro::Schema::NamedSchema]
        def child_schemas(schema)
          if schema.respond_to?(:fields)
            schema.fields.map(&:type)
          elsif schema.respond_to?(:values)
            [schema.values]
          elsif schema.respond_to?(:items)
            [schema.items]
          elsif schema.respond_to?(:schemas)
            schema.schemas
          else
            []
          end
        end

        # @param schemas [Array<Avro::Schema::NamedSchema>]
        # @return [Array<Avro::Schema::NamedSchema>]
        def collect_all_schemas(schemas)
          schemas.dup.each do |schema|
            schemas.concat(collect_all_schemas(child_schemas(schema)))
          end
          schemas.select { |s| s.respond_to?(:name) }.uniq
        end

        # @param schema_base [Deimos::SchemaBackends::Base]
        # @param key_schema_base[Avro::Schema::NamedSchema]
        def generate_class_from_schema_base(schema_base, key_schema_base: nil)
          schemas = collect_all_schemas(schema_base.schema_store.schemas.values)

          sub_schemas = schemas.reject { |s| s.name == schema_base.schema }
          @sub_schema_templates = sub_schemas.map do |schema|
            _generate_class_template_from_schema(schema)
          end

          main_schema = schemas.find { |s| s.name == schema_base.schema }
          class_template = _generate_class_template_from_schema(main_schema, key_schema_base)
          @main_class_definition = class_template

          file_prefix = main_schema.name.underscore
          namespace_path = main_schema.namespace.tr('.', '/')
          filename = "#{Deimos.config.schema.generated_class_path}/#{namespace_path}/#{file_prefix}.rb"
          template(SCHEMA_CLASS_FILE, filename, force: true)
        end

        # Format a given field into its appropriate to_h representation.
        # @param field[Deimos::SchemaField]
        # @return [String]
        def field_to_h(field)
          res = "'#{field.name}' => @#{field.name}"
          field_base_type = _schema_base_class(field.type).type_sym

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

          res + (field.name == @fields.last.name ? '' : ',')
        end

      end

      desc 'Generate a class based on configured consumer and producers.'
      # :nodoc:
      def generate
        _validate
        Rails.logger.info("Generating schemas from Deimos.config to #{Deimos.config.schema.generated_class_path}")
        Deimos.config.producer_objects.each do |config|
          schema_name = config.schema
          namespace = config.namespace || Deimos.config.producers.schema_namespace
          key_schema_name = config.key_config[:schema]
          generate_classes(schema_name, namespace, key_schema_name)
        end

        Deimos.config.consumer_objects.each do |config|
          schema_name = config.schema
          namespace = config.namespace
          key_schema_name = config.key_config[:schema]
          generate_classes(schema_name, namespace, key_schema_name)
        end
      end

    private

      # Determines if Schema Class Generation can be run.
      # @raise if Schema Backend is not of a Avro-based class
      def _validate
        backend = Deimos.config.schema.backend.to_s
        raise 'Schema Class Generation requires an Avro-based Schema Backend' if backend !~ /^avro/
      end

      # @param schema[Avro::Schema::NamedSchema]
      # @param key_schema_base[Avro::Schema::NamedSchema]
      # @return [String]
      def _generate_class_template_from_schema(schema, key_schema_base=nil)
        _set_instance_variables(schema, key_schema_base)

        temp = schema.is_a?(Avro::Schema::RecordSchema) ? _record_class_template : _enum_class_template
        res = ERB.new(temp, nil, '-')
        res.result(binding)
      end

      # @param schema[Avro::Schema::NamedSchema]
      # @param key_schema_base[Avro::Schema::NamedSchema]
      def _set_instance_variables(schema, key_schema_base=nil)
        schema_is_record = schema.is_a?(Avro::Schema::RecordSchema)
        @current_schema = schema
        return unless schema_is_record

        @fields = fields(schema)
        if key_schema_base.present?
          key_schema_base.load_schema
          key_schema = key_schema_base.schema_store.schemas.values.first
          @fields << Deimos::SchemaField.new('payload_key', key_schema, [], nil)
        end
        @initialization_definition = _initialization_definition
        @field_assignments = _field_assignments
      end

      # Defines the initialization method for Schema Records with one keyword argument per line
      # @return [String] A string which defines the method signature for the initialize method
      def _initialization_definition
        arguments = @fields.map do |schema_field|
          arg = "#{schema_field.name}:"
          arg += _field_default(schema_field)
          arg.strip
        end

        result = "def initialize(#{arguments.first}"
        arguments[1..-1].each_with_index do |arg, _i|
          result += ",#{INITIALIZE_WHITESPACE}#{arg}"
        end
        "#{result})"
      end

      # @param [SchemaField]
      # @return [String]
      def _field_default(field)
        default = field.default
        return ' nil' if default == :no_default || default.nil? || IGNORE_DEFAULTS.include?(field.name)

        case field.type.type_sym
        when :string
          " '#{default}'"
        when :record
          schema_name = Deimos::SchemaBackends::AvroBase.schema_classname(field.type)
          class_instance = Utils::SchemaClass.instance(field.default, schema_name)
          " #{class_instance.to_h}"
        else
          " #{default}"
        end
      end

      # Overrides default attr accessor methods
      # @return [Array<String>]
      def _field_assignments
        result = []
        @fields.each do |field|
          field_type = field.type.type_sym # Record, Union, Enum, Array or Map
          schema_base_type = _schema_base_class(field.type)
          field_base_type = _field_type(schema_base_type)
          method_argument = %i(array map).include?(field_type) ? 'values' : 'value'
          is_schema_class = %i(record enum).include?(schema_base_type.type_sym)

          field_initialization = method_argument

          if is_schema_class
            field_initialization = "#{field_base_type}.initialize_from_value(value)"
          end

          result << {
            field: field,
            field_type: field_type,
            is_schema_class: is_schema_class,
            method_argument: method_argument,
            deimos_type: deimos_field_type(field),
            field_initialization: field_initialization
          }
        end

        result
      end

      # Converts Avro::Schema::NamedSchema's to String form for generated YARD docs.
      # Recursively handles the typing for Arrays, Maps and Unions.
      # @param avro_schema [Avro::Schema::NamedSchema]
      # @return [String] A string representation of the Type of this SchemaField
      def _field_type(avro_schema)
        Deimos::SchemaBackends::AvroBase.field_type(avro_schema)
      end

      # Returns the base class for this schema. Decodes Arrays, Maps and Unions
      # @param avro_schema [Avro::Schema::NamedSchema]
      # @return [Avro::Schema::NamedSchema]
      def _schema_base_class(avro_schema)
        Deimos::SchemaBackends::AvroBase.schema_base_class(avro_schema)
      end

      # An ERB template for schema record classes
      # @return [String]
      def _record_class_template
        File.read(SCHEMA_RECORD_PATH).strip
      end

      # An ERB template for schema enum classes
      # @return [String]
      def _enum_class_template
        File.read(SCHEMA_ENUM_PATH).strip
      end
    end
  end
end
