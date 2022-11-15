# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record/migration'
require 'generators/deimos/schema_class_generator'
require 'rails/version'
require 'erb'

# Generates a new Active Record Consumer, as well
# as all the necessary files and configuration.
# Streamlines the creation process into a single flow.
module Deimos
  module Generators
    # Generator for ActiveRecordConsumer db migration, Rails model, Consumer, Consumer config
    # and Deimos Schema class
    class ActiveRecordConsumerGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      if Rails.version < '4'
        extend(ActiveRecord::Generators::Migration)
      else
        include ActiveRecord::Generators::Migration
      end
      source_root File.expand_path('active_record_consumer/templates', __dir__)

      argument :full_schema, desc: 'The fully qualified schema name.', required: true
      argument :config_path, desc: 'The path to the deimos configuration file, relative to the root directory.', required: false

      no_commands do

        # Creates database migration for creating new table
        def create_db_migration
          migration_template('migration.rb', "#{db_migrate_path}/create_#{table_name.underscore}.rb")
        end

        # Creates Rails Model
        def create_rails_model
          template('model.rb', "app/models/#{model_name}.rb")
        end

        # Creates Kafka Consumer file
        def create_consumer
          template('consumer.rb', "app/lib/kafka/models/#{consumer_name.underscore}.rb")
        end

        # Adds consumer config to config file.
        # Defaults to deimos.rb if config_path arg is not specified.
        def create_consumer_config
          config_file = 'deimos.rb'
          config_file_path = "#{initializer_path}/#{config_file}"
          config_file_path = config_path if config_path.present?

          if File.exist?(config_file_path)
            config_template = File.expand_path(find_in_source_paths('config.rb'))
            insert_into_file(config_file_path.to_s, CapturableERB.new(::File.binread(config_template)).result(binding))
          else
            template('config.rb', config_file_path.to_s)
          end
        end

        # Generates schema classes
        def create_deimos_schema_class
          Deimos::Generators::SchemaClassGenerator.start
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

        # @return [String]
        def migration_version
          "[#{ActiveRecord::Migration.current_version}]"
        rescue StandardError
          ''
        end

        # @return [String]
        def table_class
          table_name.classify
        end

        # @return [String]
        def schema
          last_dot = self.full_schema.rindex('.')
          self.full_schema[last_dot + 1..-1]
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

        # @return [String]
        def table_name
          schema.tableize
        end

        # @return [String]
        def model_name
          table_name.underscore.singularize
        end

        # @return [String]
        def consumer_name
          "#{schema.classify}Consumer"
        end

        # @return [String]
        def initializer_path
          if defined?(Rails.application) && Rails.application
            paths = Rails.application.config.paths['config/initializers']
            paths.respond_to?(:to_ary) ? paths.to_ary.first : paths.to_a.first
          else
            'config/initializers'
          end
        end

        # @return [String] Returns the name of the first field in the schema, as the key
        def key_field
          fields.first.name
        end
      end

      # desc 'Generate necessary files and configuration for a new Active Record Consumer.'
      # @return [void]
      def generate
        create_db_migration
        create_rails_model
        create_consumer
        create_consumer_config
        create_deimos_schema_class
      end
    end
  end
end
