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

class MyConsumer < Deimos::Consumer
  def consume(payload, metadata); end
end

require_relative "./lib/generators/deimos/schema_class_generator"

Deimos.configure do |deimos_config|
  deimos_config.schema.nest_child_schemas = true
  deimos_config.schema.path = "spec/schemas"
  deimos_config.schema.backend = :avro_validation
  deimos_config.schema.generated_class_path = './spec/schemas'
  deimos_config.schema.use_full_namespace = true
  deimos_config.schema.schema_namespace_map = {
    'com' => 'Schemas',
    'com.my-namespace.my-suborg' => %w(Schemas MyNamespace)
  }

  consumer do
    class_name 'MyConsumer'
    topic 'MyTopic'
    schema 'Generated'
    namespace 'com.my-namespace'
    key_config field: :a_string
  end

  consumer do
    class_name 'MyConsumer'
    topic 'MyTopic'
    schema 'MySchemaWithComplexTypes'
    namespace 'com.my-namespace'
    key_config field: :test_id
  end

  consumer do
    class_name 'MyConsumer'
    topic 'MyTopic'
    schema 'MySchemaWithCircularReference'
    namespace 'com.my-namespace'
    key_config none: true
  end

  consumer do
    class_name 'MyConsumer'
    topic 'MyTopic'
    schema 'MyNestedSchema'
    namespace 'com.my-namespace'
    key_config field: :test_id
  end

  consumer do
    class_name 'MyConsumer'
    topic 'MyTopic'
    schema 'MyLongNamespaceSchema'
    namespace 'com.my-namespace.my-suborg'
    key_config field: :test_id
  end

  producer do
    class_name 'MyConsumer'
    topic 'MyTopic'
    schema 'MySchema'
    namespace 'com.my-namespace'
    key_config schema: 'MySchema_key'
  end
end

Deimos::Generators::SchemaClassGenerator.new.generate
