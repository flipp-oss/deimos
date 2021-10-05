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
          schema_base = Deimos::SchemaBackends::AvroBase.new(schema: schema_name, namespace: namespace)
          schema_base.load_schema
          if key_schema_name.present?
            key_schema_base = Deimos::SchemaBackends::AvroBase.new(schema: key_schema_name, namespace: namespace)
            key_schema_base.load_schema
          end
          generate_class_from_schema_base(schema_base, key_schema_base: key_schema_base)

          return if key_schema_base.nil?

          generate_class_from_schema_base(key_schema_base)
        end

        # @param schema_base [Deimos::SchemaBackends::AvroBase]
        def generate_class_from_schema_base(schema_base, key_schema_base: nil)
          schemas = schema_base.schema_store.schemas.values
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

          template('schema_class.rb', filename, force: true)
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

        temp = schema.type_sym == :record ? _record_class_template : _enum_class_template
        res = ERB.new(temp, nil, '-')
        res.result(binding)
      end

      # @param schema[Avro::Schema::NamedSchema]
      # @param key_schema_base[Avro::Schema::NamedSchema]
      def _set_instance_variables(schema, key_schema_base=nil)
        @current_schema = schema
        @schema_has_key = key_schema_base.present?
        @fields = fields(schema) if schema.type_sym == :record
        if @schema_has_key
          key_schema_base.load_schema
          key_schema = key_schema_base.schema_store.schemas.values.first
          @fields << Deimos::SchemaField.new('payload_key', key_schema, [], nil)
        end
        @initialization_definition = _initialization_definition if schema.type_sym == :record
        @field_assignments = schema.type_sym == :record ? _field_assignments : {}
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
        %{
  # Autogenerated Schema for Record at <%= @current_schema.namespace %>.<%= @current_schema.name %>
  class <%= Deimos::SchemaBackends::AvroBase.schema_classname(@current_schema) %> < Deimos::SchemaClass::Record
<%- if @field_assignments.select{ |h| h[:is_schema_class] }.any? -%>
    ### Attribute Readers ###
  <%- @field_assignments.select{ |h| h[:is_schema_class] }.each do |method_definition| -%>
    # @return [<%= method_definition[:deimos_type] %>]
    attr_reader :<%= method_definition[:field].name %>
  <%- end -%>

<% end -%>
<%- if @field_assignments.select{ |h| !h[:is_schema_class] }.any? -%>
    ### Attribute Accessors ###
  <%- @field_assignments.select{ |h| !h[:is_schema_class] }.each do |method_definition| -%>
    # @param <%= method_definition[:method_argument] %> [<%= method_definition[:deimos_type] %>]
    attr_accessor :<%= method_definition[:field].name %>
  <%- end -%>

<% end -%>
<%- if @field_assignments.select{ |h| h[:is_schema_class] }.any? -%>
    ### Attribute Writers ###
  <%- @field_assignments.select{ |h| h[:is_schema_class] }.each do |method_definition| -%>
    # @param <%= method_definition[:method_argument] %> [<%= method_definition[:deimos_type] %>]
    def <%= method_definition[:field].name %>=(<%= method_definition[:method_argument] %>)
    <%- if method_definition[:field_type] == :array -%>
      @<%= method_definition[:field].name %> = values.map do |value|
        <%= method_definition[:field_initialization] %>
      end
    <%- elsif method_definition[:field_type] == :map -%>
      @<%= method_definition[:field].name %> = values.transform_values do |value|
        <%= method_definition[:field_initialization] %>
      end
    <%- else -%>
      @<%= method_definition[:field].name %> = <%= method_definition[:field_initialization] %>
    <%- end -%>
    end

  <%- end -%>
<% end -%>
    # @override
    <%= @initialization_definition %>
      super()
<%- @fields.each do |field| -%>
      self.<%= field.name %> = <%= field.name %>
<% end -%>
    end

    # @override
    def schema
      '<%= @current_schema.name %>'
    end

    # @override
    def namespace
      '<%= @current_schema.namespace %>'
    end

    # @override
    def to_h
      \{
<%- @fields.each do |field| -%>
        <%= field_to_h(field) %>
<% end -%>
      \}
    end
  end
        }.strip
      end

      # An ERB template for schema enum classes
      # @return [String]
      def _enum_class_template
        %{
  # Autogenerated Schema for Enum at <%= @current_schema.namespace %>.<%= @current_schema.name %>
  class <%= Deimos::SchemaBackends::AvroBase.schema_classname(@current_schema) %> < Deimos::SchemaClass::Enum
    # @return ['<%= @current_schema.symbols.join("', '") %>']
    attr_accessor :<%= @current_schema.name.underscore %>

    # :nodoc:
    def initialize(<%= @current_schema.name.underscore %>)
      super()
      self.<%= @current_schema.name.underscore %> = <%= @current_schema.name.underscore %>
    end

    # @override
    def symbols
      %w(<%= @current_schema.symbols.join(' ') %>)
    end

    # @override
    def to_h
      @<%= @current_schema.name.underscore %>
    end
  end
        }.strip
      end
    end
  end
end
