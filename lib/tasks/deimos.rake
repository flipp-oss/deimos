# frozen_string_literal: true

require 'generators/deimos/schema_class_generator'
require 'optparse'
require 'deimos/schema_backends/proto_schema_registry'

namespace :deimos do
  desc 'Starts Deimos in the rails environment'
  task start: :environment do
    ENV['DEIMOS_RAKE_TASK'] = 'true'
    ENV['DEIMOS_TASK_NAME'] = 'consumer'
    STDOUT.sync = true
    Rails.logger.info('Running deimos:start rake task.')
    Karafka::Server.run
  end

  desc 'Starts the Deimos database producer'
  task outbox: :environment do
    ENV['DEIMOS_RAKE_TASK'] = 'true'
    ENV['DEIMOS_TASK_NAME'] = 'outbox'
    STDOUT.sync = true
    Rails.logger.info('Running deimos:outbox rake task.')
    thread_count = ENV['THREAD_COUNT'].to_i.zero? ? 1 : ENV['THREAD_COUNT'].to_i
    Deimos.start_outbox_backend!(thread_count: thread_count)
  end

  task db_poller: :environment do
    ENV['DEIMOS_RAKE_TASK'] = 'true'
    ENV['DEIMOS_TASK_NAME'] = 'db_poller'
    STDOUT.sync = true
    Rails.logger.info('Running deimos:db_poller rake task.')
    Deimos::Utils::DbPoller.start!
  end

  desc 'Run Schema Model Generator'
  task generate_schema_classes: :environment do
    Rails.logger.info("Running deimos:generate_schema_classes")
    Deimos::Generators::SchemaClassGenerator.start
  end

  desc 'Output Protobuf key schemas'
  task generate_key_protos: :environment do
    puts "Generating Protobuf key schemas"
    Deimos.karafka_configs.each do |config|
      next if config.try(:producer_class).blank? ||
              !Deimos.schema_backend_for(config.name).is_a?(Deimos::SchemaBackends::ProtoSchemaRegistry) ||
              config.deserializers[:key].try(:key_field).blank?

      puts "Writing key proto for #{config.name}"
      backend = Deimos.schema_backend_for(config.name)
      backend.write_key_proto(Deimos.config.schema.proto_schema_key_path, config.deserializers[:key].key_field)
    end
  end
end
