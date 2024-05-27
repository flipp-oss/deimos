# frozen_string_literal: true

require 'rails/generators'
require 'rails/version'

# Generates a new consumer.
module Deimos
  module Generators
    # Generator for ActiveRecord model and migration.
    class V2Generator < Rails::Generators::Base

      class << self
        attr_accessor :original_config
      end

      source_root File.expand_path('v2/templates', __dir__)

      def config
        self.class.original_config
      end

      no_commands do
        def calculate_deimos
          configs = {}

        end
      end

      desc 'Generate and update app files for version 2.0'
      # @return [void]
      def generate
        deimos_configs = calculate_deimos
        default_configs = calculate_defaults
        consumer_configs = calculate_consumers
        producer_configs = calculate_producers
        template('karafka.rb.tt', "karafka.rb")
      end
    end
  end
end
