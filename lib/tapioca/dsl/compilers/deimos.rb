# typed: true

require 'avro_turf'
require 'avro/schema'
require 'deimos/schema_backends/avro_base'
require 'generators/deimos/schema_class_generator'

module Tapioca
  module Compilers
    class Deimos < Tapioca::Dsl::Compiler
      extend T::Sig

      ConstantType = type_member {{ fixed: T.class_of(::Deimos::SchemaClass::Record) }}

      class << self
        attr_reader :schemas, :decorated_schemas

        sig { override.returns(T::Enumerable[Module]) }
        def gather_constants
          return unless ::Deimos&.respond_to?(:config)

          return [] if ::Deimos.config.schema.output_sorbet # it'll output runtime sigs

          schema_store = ::AvroTurf::MutableSchemaStore.new(path: ::Deimos.config.schema.path)
          schema_store.load_schemas!
          @schemas = schema_store.schemas
          @decorated_schemas = Set.new
          @schemas.values.map { |s| ::Deimos::Utils::SchemaClass.schema_constant(s.name, s.namespace) }.compact
        end
      end

      sig { params(record: ::Avro::Schema::RecordSchema).returns(::FigTree::ConfigStruct)}
      def record_config(record)
        configs = ::Deimos.config.producer_objects + ::Deimos.config.consumer_objects
        configs.find { |c| c.schema == record.name && c.namespace == record.namespace }
      end

      sig { params(record: ::Avro::Schema::RecordSchema).returns(T.nilable(String))}
      def payload_key_type(record)
        config = record_config(record)
        return nil unless config
        return nil unless config.key_config[:schema]

        schema = config.key_config[:schema]
        ::Deimos::Utils::SchemaClass.schema_constant(schema, record.namespace).to_s
      end

      sig { params(record: ::Avro::Schema::RecordSchema).returns(String) }
      def tombstone_key_type(record)
        config = record_config(record)
        return nil if !config || config.key_config[:none].present?

        key_schema = nil
        if config.key_config[:schema]
          key_schema_base = ::Deimos.schema_backend(schema: config.key_config[:schema], namespace: record.namespace)
          key_schema_base.load_schema
          key_schema = key_schema_base.schema_store.schemas.values.first
        end
        ::Deimos::Generators::SchemaClassGenerator.tombstone_type(config.key_config, record, key_schema)
      end

      sig { params(enum: ::Avro::Schema::EnumSchema, path: T.nilable(String)).void }
      def decorate_enum(enum, path: nil)
        modules = ::Deimos::Utils::SchemaClass.modules_for(enum.namespace)
        schema_constant = enum.name.underscore.camelize.singularize
        full_path = modules
        full_path.push(path) if path && ::Deimos.config.schema.nest_child_schemas
        full_path.push(schema_constant)
        constant_name = full_path.join('::')
        enum_node = RBI::TEnum.new("#{constant_name}Enum")
        enum_node << RBI::TEnumBlock.new(enum.symbols)
        root << enum_node
        root.create_class(constant_name, superclass_name: 'Deimos::SchemaClass::Enum') do |klass|
          klass.create_method('initialize',
                              return_type: 'void',
                              parameters: [create_param("value", type: "#{constant_name}Enum")])
        end

      end

      sig { params(record: ::Avro::Schema::RecordSchema, path: T.nilable(String)).void }
      def decorate_record(record, path: nil)
        # don't create a cycle
        return if self.class.decorated_schemas.include?(record)
        self.class.decorated_schemas.add(record)

        modules = ::Deimos::Utils::SchemaClass.modules_for(record.namespace)
        schema_constant = record.name.underscore.camelize.singularize
        full_path = modules
        full_path.push(path) if path && ::Deimos.config.schema.nest_child_schemas
        full_path.push(schema_constant)
        constant_name = full_path.join('::')

        path = schema_constant if path.nil? # for nested classes

        payload_type = payload_key_type(record)

        root.create_class(constant_name, superclass_name: 'Deimos::SchemaClass::Record') do |klass|
          init_params = record.fields.map do |field|
            create_kw_param(field.name,
                            type: ::Deimos::SchemaBackends::AvroBase.sorbet_type(field.type, path, allow_enum_strings: true))
          end
          if payload_type
            init_params.push(create_kw_param('payload_key', type: payload_type))
          end
          klass.create_method('initialize', parameters: init_params, return_type: "void")
          if payload_type
            klass.create_method("payload_key", return_type: payload_type)
            klass.create_method("payload_key=",
                                parameters: [create_param("value", type: payload_type)],
                                return_type: 'void'
                                )
          end
          tombstone_type = tombstone_key_type(record)
          if tombstone_type
            klass.create_method("tombstone=", parameters: [create_param("key", type: tombstone_type)], return_type: "void")
          end
          record.fields.each do |field|
            klass.create_method(field.name, return_type: ::Deimos::SchemaBackends::AvroBase.sorbet_type(field.type, path))
            param = create_param("value", type: ::Deimos::SchemaBackends::AvroBase.sorbet_type(field.type, path, allow_enum_strings: true))
            klass.create_method("#{field.name}=", parameters: [param], return_type: 'void')
            check_field_for_records(field.type, path)
          end
        end
      end

      sig { params(schema: ::Avro::Schema, path: String).void }
      def check_field_for_records(schema, path)
        case schema.type_sym
        when :record
          decorate_record(schema, path: path)
        when :enum
          decorate_enum(schema, path: path)
        when :array
          check_field_for_records(schema.items, path)
        when :map
          check_field_for_records(schema.values, path)
        when :union
          schema.schemas.each { |s| check_field_for_records(s, path) }
        end
      end


      sig { override.void }
      def decorate
        instance = constant.allocate
        schema = self.class.schemas["#{instance.namespace}.#{instance.schema}"]
        decorate_record(schema)
      end

    end
  end
end
