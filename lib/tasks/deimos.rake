# frozen_string_literal: true

require 'phobos'
require 'phobos/cli'

namespace :deimos do
  desc 'Starts Deimos in the rails environment'
  task start: :environment do
    Deimos.configure do |config|
      config.publish_backend = :kafka if config.publish_backend == :kafka_async
    end
    ENV['DEIMOS_RAKE_TASK'] = 'true'
    STDOUT.sync = true
    Rails.logger.info('Running deimos:start rake task.')
    Phobos::CLI::Commands.start(%w(start --skip_config))
  end

  desc 'Starts the Deimos database producer'
  task db_producer: :environment do
    ENV['DEIMOS_RAKE_TASK'] = 'true'
    STDOUT.sync = true
    Rails.logger.info('Running deimos:db_producer rake task.')
    thread_count = ENV['THREAD_COUNT'].to_i.zero? ? 1 : ENV['THREAD_COUNT'].to_i
    Deimos.start_db_backend!(thread_count: thread_count)
  end

end
