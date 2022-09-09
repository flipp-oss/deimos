# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record/migration'

module Deimos
  module Generators
    # Generate the database backend migration.
    class DbPollerGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      if Rails.version < '4'
        extend(ActiveRecord::Generators::Migration)
      else
        include ActiveRecord::Generators::Migration
      end
      source_root File.expand_path('db_poller/templates', __dir__)
      desc 'Add migrations for the database poller'

      # @return [String]
      def migration_version
        "[#{ActiveRecord::Migration.current_version}]"
      rescue StandardError
        ''
      end

      # @return [String]
      def db_migrate_path
        if defined?(Rails.application) && Rails.application
          paths = Rails.application.config.paths['db/migrate']
          paths.respond_to?(:to_ary) ? paths.to_ary.first : paths.to_a.first
        else
          'db/migrate'
        end
      end

      # Main method to create all the necessary files
      # @return [void]
      def generate
        if Rails.version < '4'
          migration_template('rails3_migration',
                             "#{db_migrate_path}/create_db_poller.rb")
        else
          migration_template('migration',
                             "#{db_migrate_path}/create_db_poller.rb")
        end
      end
    end
  end
end
