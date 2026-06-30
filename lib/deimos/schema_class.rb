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

    # The generation settings that live under Deimos.config.avrogen and are
    # forwarded to AvroGen.config (same names on both sides).
    GENERATION_SETTINGS = %i(
      generated_class_path
      nest_child_schemas
      use_full_namespace
      schema_namespace_map
    ).freeze

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

    # Mirror the Deimos generation settings onto AvroGen.config. Deimos.config is
    # the source of truth within Deimos, so this runs on every configure (keeping
    # a reset in sync). The settings live under Deimos.config.avrogen; the legacy
    # Deimos.config.schema.* equivalents still work but emit a deprecation warning.
    # Standalone AvroGen users never trigger this and set AvroGen.config directly.
    # @!visibility private
    def self.sync_config!
      # schema.path is shared with the Avro backends, so it stays under `schema`.
      AvroGen.config.schema_path = Deimos.config.schema.path
      # Refresh AvroGen's cached schema stores on (re)configuration so they don't
      # serve stale schemas after the schema path or files change.
      AvroGen::SchemaValidator.clear_store_cache!

      GENERATION_SETTINGS.each do |key|
        AvroGen.config.send("#{key}=", generation_setting(key))
      end
    end

    # Resolve a generation setting, preferring the legacy (deprecated)
    # Deimos.config.schema.* location when it was explicitly set.
    # @!visibility private
    def self.generation_setting(key)
      if Deimos.config.schema.default_value?(key)
        Deimos.config.avrogen.send(key)
      else
        Deimos::Logging.deprecate(
          "Deimos.config.schema.#{key} is deprecated; use Deimos.config.avrogen.#{key} instead."
        )
        Deimos.config.schema.send(key)
      end
    end
  end
end
