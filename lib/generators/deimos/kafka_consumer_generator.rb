# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record/migration'
require 'rails/version'

# Generates a new consumer.
module Deimos
  module Generators
    # Generator for Kafka Consumers.
    class KafkaConsumerGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      if Rails.version < '4'
        extend(ActiveRecord::Generators::Migration)
      else
        include ActiveRecord::Generators::Migration
      end
      source_root File.expand_path('kafka_consumer/templates', __dir__)

      argument :table_name, desc: 'The table to create.', required: true
      argument :full_schema, desc: 'The fully qualified schema name.', required: true
      argument :topic_name, desc: 'Topic corresponding to the consumer.', required: true
      argument :config_file_path, desc: 'Relative path to the kafka config file.', required: true

      no_commands do

        # @return [String]
        def table_class
          self.table_name.classify
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

        # @return [String]
        def consumer_block
          "consumer do\n  topic '#{topic_name}'\n  class_name '#{table_class}Consumer'\n  namespace '#{namespace}'\n  schema '#{schema}'\n  group_id 'PLEASE FILL THIS'\nend\n"
        end
      end

      desc 'Generate consumer file, update configuration, create db migration and active record model.'
      # :nodoc:
      def generate
        Rails::Generators.invoke("deimos:active_record", [table_name, full_schema])
        template('consumer.rb', "app/lib/kafka/#{table_name.underscore}_consumer.rb")
        append_to_file(config_file_path, consumer_block)
      end
    end
  end
end

