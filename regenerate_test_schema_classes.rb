#! /usr/bin/env ruby
# frozen_string_literal: true

require 'action_controller/railtie'
require 'deimos'
require 'deimos/metrics/mock'
require 'deimos/tracing/mock'
require 'avro_gen/generator'

class DeimosApp < Rails::Application
end
DeimosApp.initialize!

# Schema class generation now lives in the avro-gen-ruby gem. Derive the configs
# from the configured Kafka topics (so keyed records keep their tombstone /
# payload_key helpers) and delegate to AvroGen.
configs = Deimos.karafka_configs.filter_map do |config|
  next if config.schema.nil?

  { schema: config.schema, namespace: config.namespace, key_config: config.key_config }
end
AvroGen::Generator.new.generate_from_configs(configs)
