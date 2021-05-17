# frozen_string_literal: true

require 'rails/generators'
require 'deimos'
require 'deimos/config/configuration'

module Deimos
  module Generators
    class SchemaModelGuardfileGenerator < Rails::Generators::Base
      source_root File.expand_path('schema_model/templates', __dir__)

      argument :schema_path,
               desc: 'The relative path to Schemas in your application.',
               required: false,
               default: Deimos.config.schema.path,
               type: :string

      no_commands do
        # Transforms a given path to the relative path of the Schemas in your application
        # proper format for Guardfile to detect changes
        #
        def parsed_schema_path
          path = schema_path.delete_prefix("#{Dir.pwd}/")
          Rails.logger.info("Generated Guardfile for path #{path}")
          path
        end
      end

      desc 'Generate a class based on an existing schema.'
      def generate
        Rails.logger.info(Deimos.config.schema.path)
        template('Guardfile', "Guardfile", force: true)
      end

    end
  end
end
