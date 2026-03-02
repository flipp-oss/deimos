# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record/migration'
require 'rails/version'

# Generates a new consumer.
module Deimos
  module Generators
    # Generator for ActiveRecord model and migration.
    class ActiveRecordGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      if Rails.version < '4'
        extend(ActiveRecord::Generators::Migration)
      else
        include ActiveRecord::Generators::Migration
      end
      source_root File.expand_path('active_record/templates', __dir__)

      argument :table_name, desc: 'The table to create.', required: true
      argument :full_schema, desc: 'The fully qualified schema name.', required: true

      no_commands do

        # @return [String]
        def db_migrate_path
          if defined?(Rails.application) && Rails.application
            paths = Rails.application.config.paths['db/migrate']
            paths.respond_to?(:to_ary) ? paths.to_ary.first : paths.to_a.first
          else
            'db/migrate'
          end
        end

        # @return [String]
        def migration_version
          "[#{ActiveRecord::Migration.current_version}]"
        rescue StandardError
          ''
        end

        # @return [String]
        def table_class
          self.table_name.classify
        end

        # @return [String]
        def schema
          last_dot = self.full_schema.rindex('.')
          self.full_schema[(last_dot + 1)..]
        end

        # @return [String]
        def namespace
          last_dot = self.full_schema.rindex('.')
          self.full_schema[0...last_dot]
        end

        # @return [Deimos::SchemaBackends::Base]
        def schema_base
          @schema_base ||= Deimos.schema_backend_class.new(schema: schema, namespace: namespace)
        end

        # @return [Array<SchemaField>]
        def fields
          schema_base.schema_fields
        end

      end

      desc 'Generate migration for a table based on an existing schema.'
      # @return [void]
      def generate
        migration_template('migration.rb', "db/migrate/create_#{table_name.underscore}.rb")
        template('model.rb', "app/models/#{table_name.underscore.singularize}.rb")
      end
    end
  end
end
