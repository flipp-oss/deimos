# frozen_string_literal: true

require_relative 'base'
require 'schema_registry_client'

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
      }.freeze

      def proto_schema(schema=@schema)
        proto = Google::Protobuf::DescriptorPool.generated_pool.lookup(schema)
        if proto.nil?
          raise "Could not find Protobuf schema '#{schema}'."
        end

        proto
      end

      # @override
      def encode_key(key_id, key, topic: nil)
        if key.respond_to?(:to_h)
          hash = if key_id
                   key_id.to_s.split('.')[...-1].each do |k|
                     key = key.with_indifferent_access[k]
                   end
                   key.to_h.with_indifferent_access.slice(key_id.split('.').last)
                 else
                   key.to_h.sort.to_h
                 end
          self.encode_proto_key(hash, topic: topic, field: key_id)
        elsif key_id
          hash = { key_id.to_s.split('.').last => key }
          self.encode_proto_key(hash, topic: topic, field: key_id)
        else
          key.to_s
        end
      end

      # @param hash [Hash]
      # @return [String]
      def encode_proto_key(hash, topic: nil)
        hash.sort.to_h.to_json
      end

      def decode_proto_key(payload)
        JSON.parse(payload)
      rescue StandardError
        payload
      end

      # @override
      def decode_key(payload, key_id)
        val = decode_proto_key(payload)
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

      def supports_key_schemas?
        false
      end

    end
  end
end
