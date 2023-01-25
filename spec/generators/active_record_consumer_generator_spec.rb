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
    FileUtils.rm_rf('spec/app') if File.exist?('spec/app')
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

  context 'with a regular flow' do

    it 'should generate a migration, model, consumer class, config and schema class with existing deimos.rb config file' do
      config_file_name = 'deimos.rb'
      FileUtils.mkdir_p(config_path)
      deimos_file_path = "#{config_path}/#{config_file_name}"
      File.new(deimos_file_path, "w")
      File.open(deimos_file_path, "w") { |f| f.write "Deimos.configure do\n\nend" }

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

      described_class.start(['com.my-namespace.Widget','field','a_string'])

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
      expect(File.read(files[0])).to match_snapshot('consumer_generator_existing_deimos_config')

      files = Dir["#{schema_class_path}/*/*.rb"]
      expect(File.read(files[0])).to match_snapshot('consumer_generator_schema_classes')
    end

  end


  context 'with different config file input' do
    it 'should generate correct config with no existing deimos.rb configuration file' do

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

      described_class.start(['com.my-namespace.Widget','field','a-string'])

      files = Dir["#{config_path}/deimos.rb"]
      expect(files.length).to eq(1)
      expect(File.read(files[0])).to match_snapshot('consumer_generator_new_deimos_config')
    end

    it 'should generate correct config for the passed in config file that contains Deimos.configure' do
      config_file_name = 'my_config.config'
      FileUtils.mkdir_p(config_path)
      my_config_file_path = "#{config_path}/#{config_file_name}"
      File.new(my_config_file_path, "w")
      File.open(my_config_file_path, "w") { |f| f.write "Deimos.configure do\n\nend" }

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

      described_class.start(['com.my-namespace.Widget','field','a-string',config_file_name])

      files = Dir["#{config_path}/*.config"]
      expect(files.length).to eq(1)
      expect(File.read(my_config_file_path)).to match_snapshot('consumer_generator_config_arg')
    end

    it 'should generate correct config for the passed in config file with missing Deimos.configure' do
      config_file_name = 'my_config.config'
      FileUtils.mkdir_p(config_path)
      my_config_file_path = "#{config_path}/#{config_file_name}"
      File.new(my_config_file_path, "w")

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

      described_class.start(['com.my-namespace.Widget','field','a-string',config_file_name])

      files = Dir["#{config_path}/*.config"]
      expect(files.length).to eq(1)
      expect(File.read(my_config_file_path)).to match_snapshot('consumer_generator_config_arg_missing_deimos_configure')
    end
  end

  context 'with different key schema arguments specified' do
    it 'should generate correct key_config when specifying key_config none: true' do
      config_file_name = 'my_config.config'
      FileUtils.mkdir_p(config_path)
      my_config_file_path = "#{config_path}/#{config_file_name}"
      File.new(my_config_file_path, "w")

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

      described_class.start(['com.my-namespace.Widget','none','true',config_file_name])

      files = Dir["#{config_path}/*.config"]
      expect(files.length).to eq(1)
      expect(File.read(my_config_file_path)).to match_snapshot('consumer_generator_key_config_none')
    end

    it 'should generate correct key_config when specifying key_config plain: true' do
      config_file_name = 'my_config.config'
      FileUtils.mkdir_p(config_path)
      my_config_file_path = "#{config_path}/#{config_file_name}"
      File.new(my_config_file_path, "w")

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

      described_class.start(['com.my-namespace.Widget','plain','true',config_file_name])

      files = Dir["#{config_path}/*.config"]
      expect(files.length).to eq(1)
      expect(File.read(my_config_file_path)).to match_snapshot('consumer_generator_key_config_plain')
    end

    it 'should generate correct key_config when specifying key_config schema: MyKeySchema-key' do
      config_file_name = 'my_config.config'
      FileUtils.mkdir_p(config_path)
      my_config_file_path = "#{config_path}/#{config_file_name}"
      File.new(my_config_file_path, "w")

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

      described_class.start(['com.my-namespace.Widget','schema','MyKeySchema-key',config_file_name])

      files = Dir["#{config_path}/*.config"]
      expect(files.length).to eq(1)
      expect(File.read(my_config_file_path)).to match_snapshot('consumer_generator_key_config_schema')
    end
  end
end
