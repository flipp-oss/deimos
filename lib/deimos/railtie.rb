# frozen_string_literal: true

# Add rake task to Rails.
class Deimos::Railtie < Rails::Railtie
  config.before_initialize do
    if ARGV[0] == "deimos:v2"
      FigTree.keep_removed_configs = true
    end
  end

  rake_tasks do
    load 'tasks/deimos.rake'
  end
end
