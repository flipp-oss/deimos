# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record/migration'
require 'generators/deimos/schema_class_generator'
require 'generators/deimos/active_record_generator'
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

      # @return [Array<String>]
      KEY_CONFIG_OPTIONS = %w(none plain schema field).freeze

      # @return [Array<String>]
      KEY_CONFIG_OPTIONS_BOOL = %w(none plain).freeze

      # @return [Array<String>]
      KEY_CONFIG_OPTIONS_STRING = %w(schema field).freeze

      source_root File.expand_path('active_record_consumer/templates', __dir__)

      argument :full_schema, desc: 'The fully qualified schema name.', required: true
      argument :key_config_type, desc: 'The kafka message key configuration type.', required: true
      argument :key_config_value, desc: 'The kafka message key configuration value.', required: true
      argument :config_path, desc: 'The path to the deimos configuration file, relative to the root directory.', required: false

      no_commands do

        # validate schema, key_config and deimos config file
        def validate_arguments
          _validate_schema
          _validate_key_config
          _validate_config_path
        end

        # Creates database migration for creating new table and Rails Model
        def create_db_migration_rails_model
          Deimos::Generators::ActiveRecordGenerator.start([table_name,full_schema])
        end

        # Creates Kafka Consumer file
        def create_consumer
          template('consumer.rb', "app/lib/kafka/models/#{consumer_name.underscore}.rb")
        end

        # Adds consumer config to config file.
        # Defaults to deimos.rb if config_path arg is not specified.
        def create_consumer_config
          if @config_file_path.nil?
            config_file = 'deimos.rb'
            @config_file_path = "#{initializer_path}/#{config_file}"
          end

          consumer_config_template = File.expand_path(find_in_source_paths('consumer_config.rb'))
          if File.exist?(@config_file_path)
            # if file has Deimos.configure statement then add consumers block after it
            if File.readlines(@config_file_path).grep(/Deimos.configure do/).size > 0
              insert_into_file(@config_file_path.to_s,
                              CapturableERB.new(::File.binread(consumer_config_template)).result(binding),
                              :after => "Deimos.configure do\n")
            else
              # if file does not have Deimos.configure statement then add it plus consumers block
              @consumer_config = CapturableERB.new(::File.binread(consumer_config_template)).result(binding)
              config_template = File.expand_path(find_in_source_paths('config.rb'))
              insert_into_file(@config_file_path.to_s,CapturableERB.new(::File.binread(config_template)).result(binding))
            end
          else
            @consumer_config = CapturableERB.new(::File.binread(consumer_config_template)).result(binding)
            template('config.rb', @config_file_path.to_s)
          end
        end

        # Generates schema classes
        def create_deimos_schema_class
          Deimos::Generators::SchemaClassGenerator.start(['--skip_generate_from_schema_files'])
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
        # if yes?('Would you like to install Rspec?')
        #   gem 'rspec-rails', group: :test
        #   after_bundle { generate 'rspec:install' }
        # end
        validate_arguments
        create_db_migration_rails_model
        create_consumer
        create_consumer_config
        create_deimos_schema_class
      end

      private

      # Determines if Schema Class Generation can be run.
      # @raise if Schema Backend is not of a Avro-based class
      def _validate_schema
        backend = Deimos.config.schema.backend.to_s
        raise 'Schema Class Generation requires an Avro-based Schema Backend' if backend !~ /^avro/
      end

      def _validate_key_config
        @key_config_hash = {}
        if KEY_CONFIG_OPTIONS_BOOL.include?(key_config_type)
          @key_config_hash[key_config_type] = true
        elsif KEY_CONFIG_OPTIONS_STRING.include?(key_config_type)
          @key_config_hash[key_config_type] = key_config_value
        else
          return ' nil'
        end
      end

      def _validate_config_path
        if config_path.present?
          @config_file_path = "#{initializer_path}/#{config_path}"
          raise 'Configuration file does not exist!' unless File.exist?(@config_file_path)
        end
      end
    end
  end
end
