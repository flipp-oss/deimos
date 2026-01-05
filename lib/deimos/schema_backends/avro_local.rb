# frozen_string_literal: true

require_relative 'avro_base'

module Deimos
  module SchemaBackends
    # Encode / decode using local Avro encoding.
    class AvroLocal < AvroBase
      # @override
      def decode_payload(payload, schema:)
        stream = StringIO.new(payload)
        schema = @schema_store.find(@namespace + '.' + schema)
        reader = Avro::IO::DatumReader.new(nil, schema)
        Avro::DataFile::Reader.new(stream, reader).first
      end

      # @override
      def encode_payload(payload, schema: nil, subject: nil)
        stream = StringIO.new
        schema = schema_store.find(@namespace + '.' + schema)
        writer = Avro::IO::DatumWriter.new(schema)

        dw = Avro::DataFile::Writer.new(stream, writer, schema)
        dw << payload.to_h
        dw.close
        stream.string
      end

    end
  end
end
