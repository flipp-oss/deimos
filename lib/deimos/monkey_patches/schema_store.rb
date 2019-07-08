# frozen_string_literal: true

require 'avro_turf/schema_store'

# Allows us to add in-memory schemas to the schema store in
# addition to the ones stored in the file system.
class AvroTurf::SchemaStore
  attr_accessor :schemas

  # @param schema_hash [Hash]
  def add_schema(schema_hash)
    name = schema_hash['name']
    namespace = schema_hash['namespace']
    full_name = Avro::Name.make_fullname(name, namespace)
    return if @schemas.key?(full_name)

    Avro::Schema.real_parse(schema_hash, @schemas)
  end
end
