# frozen_string_literal: true

require 'generators/deimos/schema_class_generator'
require 'fileutils'

RSpec.describe Deimos::Generators::SchemaClassGenerator do
  let(:schema_class_path) { 'app/lib/schema_classes/com/my-namespace' }
  let(:expected_files) { Dir['spec/schema_classes/*.rb'] }
  let(:files) { Dir["#{schema_class_path}/*.rb"] }

  before(:each) do
    Deimos.configure do
      schema.generated_class_path('app/lib/schema_classes')
    end
  end

  after(:each) do
    FileUtils.rm_rf(schema_class_path) if File.exist?(schema_class_path)
  end

  describe 'A Schema' do
    before(:each) do
      described_class.start(['com.my-namespace.Generated'])
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

  describe 'A Nested Schema' do
    before(:each) do
      described_class.start(['com.my-namespace.MyNestedSchema'])
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

  it 'should generate all the schema model classes in schema.path' do
    described_class.start([])
    my_namespace_files = Dir['app/lib/schema_classes/com/my-namespace/*.rb']
    request_files = Dir['app/lib/schema_classes/com/my-namespace/request/*.rb']
    response_files = Dir['app/lib/schema_classes/com/my-namespace/response/*.rb']
    expect(my_namespace_files.length).to eq(15)
    expect(request_files.length).to eq(3)
    expect(response_files.length).to eq(3)
  end

end
