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
      INITIALIZE_WHITESPACE = "\n#{' ' * 19}"
      IGNORE_DEFAULTS = %w(message_id timestamp).freeze

      source_root File.expand_path('schema_class/templates', __dir__)

      no_commands do
        # Retrieve the fields from this Avro Schema
        # @return [Array<SchemaField>]
        def fields
          @current_schema.fields.map do |field|
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
          schema_base = Deimos::SchemaBackends::AvroBase.new(schema: schema_name, namespace: namespace)
          generate_classes_from_schema_base(schema_base)

          return if key_schema_name.nil?

          key_schema_base = Deimos::SchemaBackends::AvroBase.new(schema: key_schema_name, namespace: namespace)
          generate_classes_from_schema_base(key_schema_base, is_key_schema: true)
        end

        # @param schema_base [Deimos::SchemaBackends::AvroBase]
        def generate_classes_from_schema_base(schema_base, is_key_schema: false)
          schema_base.load_schema
          schema_base.schema_store.schemas.each_value do |schema|
            @current_schema = schema
            @schema_is_key = is_key_schema
            @initialization_definition = _initialization_definition if schema.type_sym == :record
            @field_assignments = schema.type_sym == :record ? _field_assignments : {}
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

          res + (field.name == fields.last.name ? '' : ',')
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

      # Defines the initialization method for Schema Records with one keyword argument per line
      # @return [String] A string which defines the method signature for the initialize method
      def _initialization_definition
        arguments = fields.map do |schema_field|
          arg = "#{schema_field.name}:"
          arg += _field_default(schema_field)
          arg.strip
        end
        arguments += ['payload_key: nil'] unless @schema_is_key

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
          class_instance = schema_class_instance(field.default, schema_name)
          " #{class_instance.to_h}"
        else
          " #{default}"
        end
      end

      # Overrides default attr accessor methods
      # @return [Array<String>]
      def _field_assignments
        result = []
        fields.each do |field|
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
    end
  end
end
