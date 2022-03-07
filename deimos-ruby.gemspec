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
  spec.required_ruby_version = Gem::Requirement.new('>= 2.6.0')

  spec.add_dependency('avro_turf', '~> 0.11')
  spec.add_dependency('fig_tree', '~> 0.0.2')
  spec.add_dependency('phobos', '>= 1.9', '< 3.0')
  spec.add_dependency('ruby-kafka', '< 2')
  spec.add_dependency('sigurd', '~> 0.0.1')
  spec.metadata['rubygems_mfa_required'] = 'true'
end
