# frozen_string_literal: true

require 'generators/deimos/schema_class_generator'
require 'optparse'

namespace :deimos do
  desc 'Starts Deimos in the rails environment'
  task start: :environment do
    Deimos.configure do |config|
      config.producers.backend = :kafka if config.producers.backend == :kafka_async
    end
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

end
