# frozen_string_literal: true

require 'generators/deimos/kafka_consumer_generator'

RSpec.describe Deimos::Generators::KafkaConsumerGenerator do

  before(:each) do
    FileUtils.touch('configure.rb')
  end

  after(:each) do
    FileUtils.rm_rf('db') if File.exist?('db')
    FileUtils.rm_rf('app') if File.exist?('app')
    FileUtils.rm('configure.rb') if File.exist?('configure.rb')
  end

  it 'should generate a migration' do
    expect(Dir['db/migrate/*.rb']).to be_empty
    expect(Dir['app/models/*.rb']).to be_empty
    expect(Dir['app/lib/kafka/*.rb']).to be_empty
    described_class.start(['generated_table', 'com.my-namespace.Generated', 'GeneratedTopic', 'configure.rb'])
    files = Dir['db/migrate/*.rb']
    expect(files.length).to eq(1)
    results = <<~MIGRATION
      class CreateGeneratedTable < ActiveRecord::Migration[6.1]
        def up
          if table_exists?(:generated_table)
            warn "generated_table already exists, exiting"
            return
          end
          create_table :generated_table do |t|
            t.string :a_string
            t.integer :a_int
            t.bigint :a_long
            t.float :a_float
            t.float :a_double
            t.string :an_enum
            t.json :an_array
            t.json :a_map
            t.json :a_record
          end
      
          # TODO add indexes as necessary
        end
      
        def down
          return unless table_exists?(:generated_table)
          drop_table :generated_table
        end
      
      end
    MIGRATION
    expect(File.read(files[0])).to eq(results)
    model = <<~MODEL
      class GeneratedTable < ApplicationRecord
        enum an_enum: {sym1: 'sym1', sym2: 'sym2'}
      end
    MODEL
    consumer = <<~consumer
      class GeneratedTableConsumer < Deimos::Consumer
      
        # Consume the incoming topic
        # @param payload [Hash]
        # @param metadata [Hash]
        def consume(payload, metadata)
        end
      end
    consumer
    consumer_config_block = <<~consumer_config_block
      consumer do
        topic 'GeneratedTopic'
        class_name 'GeneratedTableConsumer'
        namespace 'com.my-namespace'
        schema 'Generated'
        group_id 'PLEASE FILL THIS'
      end
    consumer_config_block
    expect(File.read('app/models/generated_table.rb')).to eq(model)
    expect(File.read('app/lib/kafka/generated_table_consumer.rb')).to eq(consumer)
    expect(File.read('configure.rb')).to eq(consumer_config_block)
  end

end
