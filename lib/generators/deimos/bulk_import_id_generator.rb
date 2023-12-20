# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record/migration'
require 'rails/version'

# Generates a migration for bulk import ID in consumer.
module Deimos
  module Generators
    # Generator for ActiveRecord model and migration.
    class BulkImportIdGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      include ActiveRecord::Generators::Migration

      argument :table_name, desc: 'The table to add bulk import column.', required: true
      argument :column_name, desc: 'The bulk import ID column name.', default: 'bulk_import_id'

      source_root File.expand_path('bulk_import_id/templates', __dir__)
      desc 'Add column migration to the given table and name'

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
      end

      # For a given table_name and column_name, create a migration to add the column
      # column_name defaults to bulk_import_id
      # @return [void]
      def generate
        Rails.logger.info("Arguments: #{table_name},#{column_name}")
        migration_template('migration.rb',
                           "#{db_migrate_path}/add_#{column_name}_column_to_#{table_name}.rb")
      end
    end
  end
end
