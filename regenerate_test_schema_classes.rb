#! /usr/bin/env ruby
require 'action_controller/railtie'
require 'deimos'
require 'deimos/metrics/mock'
require 'deimos/tracing/mock'
# not sure why "require deimos/utils/schema_class" doesn't work
require_relative 'lib/deimos/utils/schema_class'

class DeimosApp < Rails::Application
end
DeimosApp.initialize!

Deimos::Generators::SchemaClassGenerator.new.generate
