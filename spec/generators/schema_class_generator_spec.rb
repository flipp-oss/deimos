# frozen_string_literal: true

require 'generators/deimos/schema_class_generator'
require 'fileutils'

RSpec.describe Deimos::Generators::SchemaClassGenerator do
  let(:schema_class_path) { 'app/lib/schema_classes/com/my-namespace' }
  let(:expected_files) { Dir['spec/schema_classes/*.rb'] }
  let(:files) { Dir["#{schema_class_path}/*.rb"] }

  before(:each) do
    Deimos.config.reset!
    Deimos.configure do
      schema.path 'spec/schemas/'
      schema.generated_class_path('app/lib/schema_classes')
      schema.backend :avro
    end
  end

  after(:each) do
    FileUtils.rm_rf(schema_class_path) if File.exist?(schema_class_path)
  end

  context 'A Consumers Schema' do
    before(:each) do
      Deimos.configure do
        consumer do
          class_name 'ConsumerTest::MyConsumer'
          topic 'MyTopic'
          schema 'Generated'
          namespace 'com.my-namespace'
          key_config field: :a_string
        end
      end
      described_class.start
    end

    it 'should generate the correct number of classes' do
      expect(files.length).to eq(3)
    end

    %w(generated a_record an_enum).each do |klass|
      it "should generate a schema class for #{klass}" do
        generated_path = files.select { |f| f =~ /#{klass}/ }.first
        expected_path = expected_files.select { |f| f =~ /#{klass}/ }.first

        expect(FileUtils.compare_file(generated_path, expected_path)).to be_truthy
      end
    end
  end

  context 'A Producers Schema with a Key' do
    before(:each) do
      Deimos.configure do
        producer do
          class_name 'ConsumerTest::MyConsumer'
          topic 'MyTopic'
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config schema: 'MySchema-key'
        end
      end
      described_class.start
    end

    it 'should generate the correct number of classes' do
      expect(files.length).to eq(2)
    end

    %w(my_schema my_schema_key).each do |klass|
      it "should generate a schema class for #{klass}" do
        generated_path = files.select { |f| f =~ /#{klass}/ }.first
        expected_path = expected_files.select { |f| f =~ /#{klass}/ }.first

        expect(FileUtils.compare_file(generated_path, expected_path)).to be_truthy
      end
    end
  end

  context 'A Consumers Nested Schema' do
    before(:each) do
      Deimos.configure do
        consumer do
          class_name 'ConsumerTest::MyConsumer'
          topic 'MyTopic'
          schema 'MyNestedSchema'
          namespace 'com.my-namespace'
          key_config field: :test_id
        end
      end
      described_class.start
    end

    it 'should generate the correct number of classes' do
      expect(files.length).to eq(2)
    end

    %w(my_nested_schema my_nested_record).each do |klass|
      it "should generate a schema class for #{klass}" do
        generated_path = files.select { |f| f =~ /#{klass}/ }.first
        expected_path = expected_files.select { |f| f =~ /#{klass}/ }.first

        expect(FileUtils.compare_file(generated_path, expected_path)).to be_truthy
      end
    end
  end

  context 'A mix of Consumer and Producer Schemas' do
    before(:each) do
      Deimos.configure do
        producer do
          class_name 'ConsumerTest::MyConsumer'
          topic 'MyTopic'
          schema 'Generated'
          namespace 'com.my-namespace'
          key_config field: :a_string
        end

        consumer do
          class_name 'ConsumerTest::MyConsumer'
          topic 'MyTopic'
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config field: :test_id
        end

        producer do
          class_name 'ConsumerTest::MyConsumer'
          topic 'MyTopic'
          schema 'MyNestedSchema'
          namespace 'com.my-namespace'
          key_config field: :test_id
        end
      end
      described_class.start
    end

    it 'should generate the correct number of classes' do
      expect(files.length).to eq(6)
    end

    %w(generated a_record an_enum my_schema my_nested_schema my_nested_record).each do |klass|
      it "should generate a schema class for #{klass}" do
        generated_path = files.select { |f| f =~ /#{klass}\.rb/ }.first
        expected_path = expected_files.select { |f| f =~ /#{klass}\.rb/ }.first

        expect(FileUtils.compare_file(generated_path, expected_path)).to be_truthy
      end
    end
  end

end
