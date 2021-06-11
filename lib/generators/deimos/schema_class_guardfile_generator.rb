# frozen_string_literal: true

require 'rails/generators'
require 'deimos/config/configuration'

# Generates a Guardfile for automatic SchemaClass generation
module Deimos
  module Generators
    # Generator the Guardfile used in SchemaClass generation
    class SchemaClassGuardfileGenerator < Rails::Generators::Base
      source_root File.expand_path('schema_class/templates', __dir__)

      argument :schema_path,
               desc: 'The relative path to Schemas in your application.',
               required: false,
               default: Deimos.config.schema.path,
               type: :string

      no_commands do
        # Transforms a given path to the relative path of the Schemas in your application
        # proper format for Guardfile to detect changes
        def parsed_schema_path
          path = schema_path.delete_prefix("#{Dir.pwd}/")
          Rails.logger.info("Generated Guardfile for path #{path}")
          path
        end
      end

      desc 'Generate a class based on an existing schema.'
      # :nodoc:
      def generate
        # TODO: Create new, OR add to existing if not exists
        Rails.logger.info(Deimos.config.schema.path)
        template('Guardfile', 'Guardfile', force: true)
      end
    end
  end
end
