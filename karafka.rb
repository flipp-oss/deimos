# frozen_string_literal: true

# Used in regenerate_test_schema_classes.rb

class MyConsumer < Deimos::Consumer
  def consume(payload, metadata)
  end
end

require_relative './lib/generators/deimos/schema_class_generator'

Deimos.configure do |deimos_config|
  deimos_config.schema.nest_child_schemas = true
  deimos_config.schema.path = 'spec/schemas'
  deimos_config.schema.backend = :avro_validation
  deimos_config.schema.generated_class_path = './spec/schemas'
  deimos_config.schema.use_full_namespace = true
  deimos_config.schema.schema_namespace_map = {
    'com' => 'Schemas',
    'com.my-namespace.my-suborg' => %w(Schemas MyNamespace)
  }
end

class KarafkaApp < Karafka::App
  setup do
    config.kafka = {
      "bootstrap.servers": '127.0.0.1:9092'
    }
  end
  routes.draw do
    topic 'MyTopic' do
      consumer MyConsumer
      schema 'Generated'
      namespace 'com.my-namespace'
      key_config({ field: :a_string })
    end

    topic 'MyTopic2' do
      consumer MyConsumer
      schema 'MySchemaWithComplexTypes'
      namespace 'com.my-namespace'
      key_config({ field: :test_id })
    end

    topic 'MyTopic3' do
      consumer MyConsumer
      schema 'MySchemaWithCircularReference'
      namespace 'com.my-namespace'
      key_config({ none: true })
    end

    topic 'MyTopic4' do
      consumer MyConsumer
      schema 'MyNestedSchema'
      namespace 'com.my-namespace'
      key_config({ field: :test_id })
    end

    topic 'MyTopic5' do
      consumer MyConsumer
      schema 'MyLongNamespaceSchema'
      namespace 'com.my-namespace.my-suborg'
      key_config({ field: :test_id })
    end

    topic 'MyTopic6' do
      producer_class MyConsumer
      schema 'MySchema'
      namespace 'com.my-namespace'
      key_config({ schema: 'MySchema_key' })
    end

  end
end
