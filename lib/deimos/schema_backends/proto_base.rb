# frozen_string_literal: true

require_relative 'base'
require 'proto_turf'

module Deimos
  module SchemaBackends
    # Encode / decode using Avro, either locally or via schema registry.
    class ProtoBase < Base
      SQL_MAP = {
        string: :string,
        int32: :integer,
        uint32: :integer,
        sint32: :integer,
        fixed32: :integer,
        sfixed32: :integer,
        int64: :bigint,
        uint64: :bigint,
        sint64: :bigint,
        fixed64: :bigint,
        sfixed64: :bigint,
        bool: :boolean,
        bytes: :string,
        float: :float,
        message: :record
      }
      def proto_schema(schema=@schema)
        Google::Protobuf::DescriptorPool.generated_pool.lookup(schema)
      end

      # @override
      def encode_key(key_id, key, topic: nil)
        if key.is_a?(Hash)
          key_id ? key[key_id].to_s : key.sort.to_h.to_json
        else
          key.to_s
        end
      end

      # @override
      def decode_key(payload, key_id)
        val = JSON.parse(payload) rescue payload
        key_id ? val[key_id.to_s] : val
      end

      # :nodoc:
      def sql_type(field)
        type = field.type
        return SQL_MAP[type] if SQL_MAP[type]
        return :array if type.repeated?

        if type == :double
          warn('Protobuf `double` type turns into SQL `float` type. Please ensure you have the correct `limit` set.')
          return :float
        end

        :string
      end

      def coerce(payload)
        payload
      end

      # @override
      def coerce_field(field, value)
      end

      # @override
      def schema_fields
        proto_schema.to_a.map do |f|
          SchemaField.new(f.name, f.subtype&.name || 'record', [], nil)
        end
      end

      # @override
      def validate(payload, schema:)
      end

      # @override
      def self.mock_backend
        :mock
      end

      def generate_key_schema(field_name)
        raise 'Protobuf cannot generate key schemas! Please use field_config :plain'
      end

    private

    end
  end
end
