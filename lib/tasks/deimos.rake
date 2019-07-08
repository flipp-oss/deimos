# frozen_string_literal: true

require 'phobos'
require 'phobos/cli'

namespace :deimos do
  desc 'Starts Deimos in the rails environment'
  task start: :environment do
    Deimos.configure do |config|
      config.publish_backend = :kafka_sync if config.publish_backend == :kafka_async
    end
    ENV['DEIMOS_RAKE_TASK'] = 'true'
    STDOUT.sync = true
    Rails.logger.info('Running deimos:start rake task.')
    Phobos::CLI::Commands.start(%w(start --skip_config))
  end
end
