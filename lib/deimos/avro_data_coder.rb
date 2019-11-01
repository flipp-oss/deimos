# frozen_string_literal: true

module Deimos
  # Base class for the encoder / decoder classes.
  class AvroDataCoder
    attr_accessor :schema, :namespace, :config, :schema_store

    # @param schema [String]
    # @param namespace [String]
    # @param schema_store [AvroTurf::SchemaStore]
    def initialize(schema:, namespace:, schema_store: nil)
      @schema = schema
      @namespace = namespace
      @schema_store = schema_store ||
                      AvroTurf::SchemaStore.new(path: Deimos.config.schema.path)
    end

    # @param schema [String]
    # @return [Avro::Schema]
    def avro_schema(schema=nil)
      schema ||= @schema
      @schema_store.find(schema, @namespace)
    end

  private

    # @return [AvroTurf]
    def avro_turf
      @avro_turf ||= AvroTurf.new(
        schemas_path: Deimos.config.schema.path,
        schema_store: @schema_store
      )
      @avro_turf
    end

    # @return [AvroTurf::Messaging]
    def avro_turf_messaging
      @avro_turf_messaging ||= AvroTurf::Messaging.new(
        schema_store: @schema_store,
        registry_url: Deimos.config.schema.registry_url,
        schemas_path: Deimos.config.schema.path,
        namespace: @namespace
      )
    end

    # Generate a key schema from the given value schema and key ID. This
    # is used when encoding or decoding keys from an existing value schema.
    # @param key_id [Symbol]
    # @return [Hash]
    def _generate_key_schema(key_id)
      return @key_schema if @key_schema

      value_schema = @schema_store.find(@schema, @namespace)
      key_field = value_schema.fields.find { |f| f.name == key_id.to_s }
      name = _key_schema_name(@schema)
      @key_schema = {
        'type' => 'record',
        'name' => name,
        'namespace' => @namespace,
        'doc' => "Key for #{@namespace}.#{@schema}",
        'fields' => [
          {
            'name' => key_id,
            'type' => key_field.type.type_sym.to_s
          }
        ]
      }
      @schema_store.add_schema(@key_schema)
      @key_schema
    end

    # @param value_schema [Hash]
    # @return [String]
    def _field_name_from_schema(value_schema)
      raise "Schema #{@schema} not found!" if value_schema.nil?
      if value_schema['fields'].nil? || value_schema['fields'].empty?
        raise "Schema #{@schema} has no fields!"
      end

      value_schema['fields'][0]['name']
    end

    # @param schema [String]
    # @return [String]
    def _key_schema_name(schema)
      "#{schema.gsub('-value', '')}_key"
    end
  end
end
