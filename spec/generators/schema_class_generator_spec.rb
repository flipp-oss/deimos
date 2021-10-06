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
      schema.generated_class_path 'app/lib/schema_classes'
      schema.backend :avro_local
    end
  end

  after(:each) do
    FileUtils.rm_rf(schema_class_path) if File.exist?(schema_class_path)
  end

  context 'with a Consumers Schema' do
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
      expect(files.length).to eq(1)
    end

    it 'should generate a schema class for generated' do
      generated_path = files.select { |f| f =~ /generated/ }.first
      expected_path = expected_files.select { |f| f =~ /generated/ }.first

      expect(FileUtils.compare_file(generated_path, expected_path)).to be_truthy
    end
  end

  context 'with a Consumers Schema with Complex types' do
    before(:each) do
      Deimos.configure do
        consumer do
          class_name 'ConsumerTest::MyConsumer'
          topic 'MyTopic'
          schema 'MySchemaWithComplexTypes'
          namespace 'com.my-namespace'
          key_config field: :a_string
        end
      end
      described_class.start
    end

    it 'should generate the correct number of classes' do
      expect(files.length).to eq(1)
    end

    it 'should generate a schema class for my_schema_with_complex_types' do
      generated_path = files.select { |f| f =~ /my_schema_with_complex_types/ }.first
      expected_path = expected_files.select { |f| f =~ /my_schema_with_complex_types/ }.first

      expect(FileUtils.compare_file(generated_path, expected_path)).to be_truthy
    end
  end

  context 'with a Producers Schema with a Key' do
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

  context 'with a Consumers Nested Schema' do
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
      expect(files.length).to eq(1)
    end

    it 'should generate a schema class for my_nested_schema' do
      generated_path = files.select { |f| f =~ /my_nested_schema/ }.first
      expected_path = expected_files.select { |f| f =~ /my_nested_schema/ }.first

      expect(FileUtils.compare_file(generated_path, expected_path)).to be_truthy
    end
  end

  context 'with a mix of Consumer and Producer Schemas' do
    before(:each) do
      Deimos.configure do
        consumer do
          class_name 'ConsumerTest::MyConsumer'
          topic 'MyTopic'
          schema 'Generated'
          namespace 'com.my-namespace'
          key_config field: :a_string
        end

        producer do
          class_name 'ConsumerTest::MyConsumer'
          topic 'MyTopic'
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config schema: 'MySchema-key'
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
      expect(files.length).to eq(4)
    end

    %w(generated my_schema my_schema_key my_nested_schema).each do |klass|
      it "should generate a schema class for #{klass}" do
        generated_path = files.select { |f| f =~ /#{klass}\.rb/ }.first
        expected_path = expected_files.select { |f| f =~ /#{klass}\.rb/ }.first

        expect(FileUtils.compare_file(generated_path, expected_path)).to be_truthy
      end
    end
  end

  context 'with non-avro schema backends' do
    before(:each) do
      Deimos.config.schema.backend :mock
    end

    it 'should fail to start schema class generation' do
      expect {
        described_class.start
      }.to raise_error(message='Schema Class Generation requires an Avro-based Schema Backend')
    end
  end

end
