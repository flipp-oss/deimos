# frozen_string_literal: true

require_relative 'proto_base'
require 'schema_registry_client'

module Deimos
  module SchemaBackends
    # Encode / decode using the Protobuf schema registry.
    class ProtoSchemaRegistry < ProtoBase

      # @override
      def self.mock_backend
        :proto_local
      end

      # @override
      def decode_payload(payload, schema:)
        self.class.schema_registry.decode(payload)
      end

      # @override
      def encode_payload(payload, schema: nil, subject: nil)
        msg = payload.is_a?(Hash) ? proto_schema.msgclass.new(**payload) : payload
        encoder = subject&.ends_with?('-key') ? self.class.key_schema_registry : self.class.schema_registry
        encoder.encode(msg, subject: subject)
      end

      # @override
      def encode_proto_key(key, topic: nil, field: nil)
        schema_text = SchemaRegistry::Output::JsonSchema.output(proto_schema.to_proto, path: field)
        self.class.key_schema_registry.encode(key, subject: "#{topic}-key", schema_text: schema_text)
      end

      # @override
      def decode_proto_key(payload)
        self.class.key_schema_registry.decode(payload)
      end

      # @return [SchemaRegistry::Client]
      def self.schema_registry
        @schema_registry ||= SchemaRegistry::Client.new(
          registry_url: Deimos.config.schema.registry_url,
          user: Deimos.config.schema.user,
          password: Deimos.config.schema.password,
          logger: Karafka.logger
        )
      end

      def self.key_schema_registry
        @key_schema_registry ||= SchemaRegistry::Client.new(
          registry_url: @registry_info&.url || Deimos.config.schema.registry_url,
          user: @registry_info&.user || Deimos.config.schema.user,
          password: @registry_info&.password || Deimos.config.schema.password,
          logger: Karafka.logger,
          schema_type: SchemaRegistry::Schema::ProtoJsonSchema.new
        )
      end

      # @param file [String]
      # @param field_name [String]
      def write_key_proto(file, field_name)
        return if field_name.nil?

        proto = proto_schema
        package = proto.file_descriptor.to_proto.package
        writer = SchemaRegistry::Output::ProtoText::Writer.new
        info = SchemaRegistry::Output::ProtoText::ParseInfo.new(writer, package)
        writer.write_line(%(syntax = "proto3";))
        writer.write_line("package #{package};")
        writer.writenl

        field = proto.to_proto.field.find { |f| f.name == field_name.to_s }
        writer.write_line("message #{proto.to_proto.name}Key {")
        writer.indent
        SchemaRegistry::Output::ProtoText.write_field(info, field)
        writer.dedent
        writer.write_line('}')
        path = "#{file}/#{package.gsub('.', '/')}/#{proto.to_proto.name.underscore}_key.proto"
        File.write(path, writer.string)
      end

    end
  end
end
