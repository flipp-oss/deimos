# frozen_string_literal: true

require 'avro_gen'

module Deimos
  # Backwards-compatible shim. Schema class generation moved to the avro-gen-ruby
  # gem (namespace AvroGen). Previously-generated classes that reference
  # `Deimos::SchemaClass::Record` / `Enum` / `Base` still resolve here, with a
  # one-time deprecation warning, via const_missing.
  module SchemaClass
    DEPRECATED_CONSTANTS = {
      Base: AvroGen::SchemaClass::Base,
      Record: AvroGen::SchemaClass::Record,
      Enum: AvroGen::SchemaClass::Enum
    }.freeze

    # Maps the moved generation settings from Deimos.config.schema to AvroGen.config.
    GENERATION_SETTINGS = {
      generated_class_path: :generated_class_path,
      nest_child_schemas: :nest_child_schemas,
      use_full_namespace: :use_full_namespace,
      schema_namespace_map: :schema_namespace_map
    }.freeze

    # @param name [Symbol]
    def self.const_missing(name)
      klass = DEPRECATED_CONSTANTS[name]
      return super unless klass

      Deimos::Logging.deprecate(
        "Deimos::SchemaClass::#{name} is deprecated; use AvroGen::SchemaClass::#{name} instead. " \
        'Run `rake avro:upgrade` to update generated classes.'
      )
      # Define the constant so the warning is only emitted once.
      const_set(name, klass)
      klass
    end

    # Mirror the (now-delegated) Deimos schema settings onto AvroGen.config.
    # Deimos.config.schema stays the source of truth within Deimos, so this runs
    # on every configure (keeping a reset in sync) and warns when a moved,
    # generation-specific setting was explicitly set. Standalone AvroGen users
    # never trigger this and set AvroGen.config directly.
    # @!visibility private
    def self.sync_config!
      schema = Deimos.config.schema
      # schema.path is shared with the Avro backends, so sync it without a warning.
      AvroGen.config.schema_path = schema.path
      # Refresh AvroGen's cached schema stores on (re)configuration so they don't
      # serve stale schemas after the schema path or files change.
      AvroGen::SchemaValidator.clear_store_cache!

      GENERATION_SETTINGS.each do |deimos_key, avro_key|
        AvroGen.config.send("#{avro_key}=", schema.send(deimos_key))
        next if schema.default_value?(deimos_key)

        Deimos::Logging.deprecate(
          "Deimos.config.schema.#{deimos_key} is deprecated; set AvroGen.config.#{avro_key} instead."
        )
      end
    end
  end
end
