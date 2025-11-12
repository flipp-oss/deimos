# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'deimos/version'

Gem::Specification.new do |spec|
  spec.name          = 'deimos-ruby'
  spec.version       = Deimos::VERSION
  spec.authors       = ['Daniel Orner']
  spec.email         = ['daniel.orner@wishabi.com']
  spec.summary       = 'Kafka libraries for Ruby.'
  spec.homepage      = ''
  spec.license       = 'Apache-2.0'

  spec.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_runtime_dependency('avro_turf', '>= 1.4', '< 2')
  spec.add_runtime_dependency('benchmark', '~> 0.5')
  spec.add_runtime_dependency('fig_tree', '~> 0.2.0')
  spec.add_runtime_dependency('karafka', '~> 2.0')
  spec.add_runtime_dependency('sigurd', '>= 0.1.0', '< 1.0')

  spec.add_development_dependency('activerecord-import')
  spec.add_development_dependency('activerecord-trilogy-adapter')
  spec.add_development_dependency('avro', '~> 1.9')
  spec.add_development_dependency('database_cleaner', '~> 2.1')
  spec.add_development_dependency('ddtrace', '>= 0.11')
  spec.add_development_dependency('dogstatsd-ruby', '>= 4.2')
  spec.add_development_dependency('guard', '~> 2')
  spec.add_development_dependency('guard-rspec', '~> 4')
  spec.add_development_dependency('guard-rubocop', '~> 1')
  spec.add_development_dependency('karafka-testing', '~> 2.0')
  spec.add_development_dependency('pg', '~> 1.1')
  spec.add_development_dependency('proto_turf')
  spec.add_development_dependency('rails', '~> 8.0')
  spec.add_development_dependency('rake', '~> 13')
  spec.add_development_dependency('rspec', '~> 3')
  spec.add_development_dependency('rspec_junit_formatter', '~>0.3')
  spec.add_development_dependency('rspec-rails', '~> 8.0')
  spec.add_development_dependency('rspec-snapshot', '~> 2.0')
  spec.add_development_dependency('rubocop', '0.89.0')
  spec.add_development_dependency('rubocop-rspec', '1.42.0')
  spec.add_development_dependency('sord', '>= 5.0')
  spec.add_development_dependency('sqlite3', '~> 2.7')
  spec.add_development_dependency('steep', '~> 1.0')
  spec.add_development_dependency('trilogy', '>= 0.1')
end
