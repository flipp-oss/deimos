# frozen_string_literal: true

require 'generators/deimos/schema_class_generator'
require 'fileutils'

class MultiFileSerializer
  def dump(value)
    value.keys.sort.map { |k| "#{k}:\n#{value[k]}\n" }.join("\n")
  end
end

RSpec.describe Deimos::Generators::SchemaClassGenerator do
  let(:schema_class_path) { 'spec/app/lib/schema_classes' }
  let(:files) { Dir["#{schema_class_path}/**/*.rb"].map { |f| [f, File.read(f)]}.to_h }

  before(:each) do
    Deimos.config.reset!
    Deimos.configure do
      schema.path 'spec/schemas/'
      schema.generated_class_path 'spec/app/lib/schema_classes'
      schema.backend :avro_local
    end
  end

  after(:each) do
    FileUtils.rm_rf('spec/app') if File.exist?('spec/app')
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
    end

    context 'nested true' do
      it 'should generate the correct classes' do
        Deimos.with_config('schema.nest_child_schemas' => true) do
          described_class.start
          expect(files).to match_snapshot('consumers', snapshot_serializer: MultiFileSerializer)
        end
      end
    end

    context 'nested false' do
      it 'should generate the correct classes' do
        Deimos.with_config('schema.nest_child_schemas' => false) do
          described_class.start
          expect(files).to match_snapshot('consumers-no-nest', snapshot_serializer: MultiFileSerializer)
        end
      end
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
    end

    context 'nested true' do
      it 'should generate the correct classes' do
        Deimos.with_config('schema.nest_child_schemas' => true) do
          described_class.start
          expect(files).to match_snapshot('consumers_complex_types', snapshot_serializer: MultiFileSerializer)
        end
      end
    end

    context 'nested false' do
      it 'should generate the correct classes' do
        Deimos.with_config('schema.nest_child_schemas' => false) do
          described_class.start
          expect(files).to match_snapshot('consumers_complex_types-no-nest', snapshot_serializer: MultiFileSerializer)
        end
      end
    end
  end

  context 'with a Consumers Schema with a circular reference' do
    before(:each) do
      Deimos.configure do
        consumer do
          class_name 'ConsumerTest::MyConsumer'
          topic 'MyTopic'
          schema 'MySchemaWithCircularReference'
          namespace 'com.my-namespace'
          key_config field: :a_string
        end
      end
    end

    context 'nested true' do
      it 'should generate the correct classes' do
        Deimos.with_config('schema.nest_child_schemas' => true) do
          described_class.start
          expect(files).to match_snapshot('consumers_circular', snapshot_serializer: MultiFileSerializer)
        end
      end
    end

    context 'nested false' do
      it 'should generate the correct classes' do
        Deimos.with_config('schema.nest_child_schemas' => false) do
          described_class.start
          expect(files).to match_snapshot('consumers_circular-no-nest', snapshot_serializer: MultiFileSerializer)
        end
      end
    end
  end

  context 'with a Producers Schema and a Key' do
    before(:each) do
      Deimos.configure do
        producer do
          class_name 'ConsumerTest::MyConsumer'
          topic 'MyTopic'
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config schema: 'MySchema_key'
        end
      end
    end

    context 'nested true' do
      it 'should generate the correct classes' do
        Deimos.with_config('schema.nest_child_schemas' => true) do
          described_class.start
          expect(files).to match_snapshot('producers_with_key', snapshot_serializer: MultiFileSerializer)
        end
      end
    end

    context 'nested false' do
      it 'should generate the correct classes' do
        Deimos.with_config('schema.nest_child_schemas' => false) do
          described_class.start
          expect(files).to match_snapshot('producers_with_key-no-nest', snapshot_serializer: MultiFileSerializer)
        end
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
    end

    context 'nested true' do
      it 'should generate the correct classes' do
        Deimos.with_config('schema.nest_child_schemas' => true) do
          described_class.start
          expect(files).to match_snapshot('consumers_nested', snapshot_serializer: MultiFileSerializer)
        end
      end
    end

    context 'nested false' do
      it 'should generate the correct classes' do
        Deimos.with_config('schema.nest_child_schemas' => false) do
          described_class.start
          expect(files).to match_snapshot('consumers_nested-no-nest', snapshot_serializer: MultiFileSerializer)
        end
      end
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
          key_config schema: 'MySchema_key'
        end

        producer do
          class_name 'ConsumerTest::MyConsumer'
          topic 'MyTopic'
          schema 'MyNestedSchema'
          namespace 'com.my-namespace'
          key_config field: :test_id
        end
      end
    end

    context 'with namespace folders' do
      it 'should generate the correct classes' do
        Deimos.with_config('schema.generate_namespace_folders' => true) do
          described_class.start
          expect(files).to match_snapshot('namespace_folders', snapshot_serializer: MultiFileSerializer)
        end
      end
    end

    context 'nested true' do
      it 'should generate the correct classes' do
        Deimos.with_config('schema.nest_child_schemas' => true) do
          described_class.start
          expect(files).to match_snapshot('consumers_and_producers', snapshot_serializer: MultiFileSerializer)
        end
      end
    end

    context 'nested false' do
      it 'should generate the correct classes' do
        Deimos.with_config('schema.nest_child_schemas' => false) do
          described_class.start
          expect(files).to match_snapshot('consumers_and_producers-no-nest', snapshot_serializer: MultiFileSerializer)
        end
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

  context 'with skip_generate_from_schema_files option' do
    before(:each) do
      Deimos.configure do
        consumer do
          class_name 'ConsumerTest::MyConsumer'
          topic 'MyTopic'
          schema 'Widget'
          namespace 'com.my-namespace'
          key_config field: :a_string
        end
      end
    end

    it 'should only generate class for consumer defined in config' do
      Deimos.with_config('schema.nest_child_schemas' => false) do
        described_class.start(['--skip_generate_from_schema_files'])
        expect(files).to match_snapshot('widget-skip-generate-from-schema-files', snapshot_serializer: MultiFileSerializer)
      end
    end
  end

end
