# frozen_string_literal: true

require 'bundler/gem_tasks'
begin
  require 'rspec/core/rake_task'

  RSpec::Core::RakeTask.new(:spec)
  task(default: :spec)
rescue LoadError # rubocop:disable Lint/HandleExceptions
  # no rspec available
end

import('./lib/tasks/deimos.rake')
