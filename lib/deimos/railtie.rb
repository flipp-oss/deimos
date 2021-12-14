# frozen_string_literal: true

# Add rake task to Rails.
class Deimos::Railtie < ::Rails::Railtie
  rake_tasks do
    load 'tasks/deimos.rake'
  end
end
