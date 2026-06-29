# frozen_string_literal: true

require 'avro_gen'

module Deimos
  module Utils
    # Backwards-compatible shim. The schema class helpers moved to
    # AvroGen::SchemaClass. This delegates with a deprecation warning.
    module SchemaClass
      class << self
        def method_missing(name, ...)
          if AvroGen::SchemaClass.respond_to?(name)
            Deimos::Logging.deprecate(
              "Deimos::Utils::SchemaClass.#{name} is deprecated; use AvroGen::SchemaClass.#{name} instead."
            )
            AvroGen::SchemaClass.send(name, ...)
          else
            super
          end
        end

        def respond_to_missing?(name, include_private=false)
          AvroGen::SchemaClass.respond_to?(name, include_private) || super
        end
      end
    end
  end
end
