# frozen_string_literal: true

require 'generators/deimos/active_record_consumer_generator'
require 'fileutils'
require 'tempfile'

RSpec.describe Deimos::Generators::ActiveRecordConsumerGenerator do
  let(:db_migration_path) { 'db/migrate' }
  let(:model_path) { 'app/models' }
  let(:consumer_path) { 'app/lib/kafka/models' }
  let(:config_path) { 'config/initializers' }
  let(:schema_class_path) { 'spec/app/lib/schema_classes' }

  after(:each) do
    FileUtils.rm_rf('db') if File.exist?('db')
    FileUtils.rm_rf('app') if File.exist?('app')
    FileUtils.rm_rf('config') if File.exist?('config')
  end

  before(:each) do
    Deimos.config.reset!
    Deimos.configure do
      schema.path('spec/schemas/')
      schema.generated_class_path('spec/app/lib/schema_classes')
      schema.backend(:avro_local)
      schema.generate_namespace_folders(true)
    end
  end

  it 'should generate a migration, model, consumer class, config and schema classes' do
    Deimos.configure do
      consumer do
        class_name 'ConsumerTest::MyConsumer'
        topic 'MyTopic'
        schema 'Widget'
        namespace 'com.my-namespace'
        key_config field: :a_string
      end
    end

    expect(Dir["#{db_migration_path}/*.rb"]).to be_empty
    expect(Dir["#{model_path}/*.rb"]).to be_empty
    expect(Dir["#{config_path}/*.rb"]).to be_empty
    expect(Dir["#{schema_class_path}/*.rb"]).to be_empty

    described_class.start(['com.my-namespace.Widget'])

    files = Dir["#{db_migration_path}/*.rb"]
    expect(files.length).to eq(1)
    expect(File.read(files[0])).to match_snapshot('consumer_generator_migration')

    files = Dir["#{model_path}/*.rb"]
    expect(files.length).to eq(1)
    expect(File.read(files[0])).to match_snapshot('consumer_generator_model')

    files = Dir["#{consumer_path}/*.rb"]
    expect(files.length).to eq(1)
    expect(File.read(files[0])).to match_snapshot('consumer_generator_consumer_class')

    files = Dir["#{config_path}/*.rb"]
    expect(files.length).to eq(1)
    expect(File.read(files[0])).to match_snapshot('consumer_generator_config')

    files = Dir["#{schema_class_path}/**/*.rb"].map { |f| [f, File.read(f)] }.to_h
    expect(files).to match_snapshot('consumer_generator_schema_classes', snapshot_serializer: MultiFileSerializer)
  end

  it 'should generate a migration, model, consumer class, schema classes and edit the passed in config file' do
    config_file_name = 'my_config.config'
    FileUtils.mkdir_p(config_path)
    Tempfile.new(config_file_name, config_path)
    config_path_argument = "#{config_path}/#{config_file_name}"

    Deimos.configure do
      consumer do
        class_name 'ConsumerTest::MyConsumer'
        topic 'MyTopic'
        schema 'Widget'
        namespace 'com.my-namespace'
        key_config field: :a_string
      end
    end

    expect(Dir["#{db_migration_path}/*.rb"]).to be_empty
    expect(Dir["#{model_path}/*.rb"]).to be_empty
    expect(Dir["#{schema_class_path}/*.rb"]).to be_empty

    described_class.start(['com.my-namespace.Widget', config_path_argument])

    expect(File.read(config_path_argument)).to match_snapshot('consumer_generator_config_with_config_arg')
  end

end
