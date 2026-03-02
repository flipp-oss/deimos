# frozen_string_literal: true

require 'rake'
require 'rails'
require 'deimos/schema_backends/proto_schema_registry'
require 'deimos/schema_backends/avro_validation'
require_relative 'gen/sample/v1/sample_pb'
require 'fileutils'
require 'tmpdir'

Rails.logger = Logger.new(STDOUT)
load("#{__dir__}/../lib/tasks/deimos.rake")

if Rake.application.lookup(:environment).nil?
  Rake::Task.define_task(:environment)
end

describe 'Rakefile' do
  it 'should start listeners' do
    expect(Karafka::Server).to receive(:run)
    Rake::Task['deimos:start'].invoke
  end

  describe 'generate_key_protos' do
    let(:temp_dir) { Dir.mktmpdir('deimos_rake_test') }

    before(:each) do
      Rake::Task['deimos:generate_key_protos'].reenable
      # Create the package directory structure
      FileUtils.mkdir_p(File.join(temp_dir, 'sample/v1'))
      # Configure Deimos to use the temp directory
      Deimos.config.schema.proto_schema_key_path = temp_dir
    end

    after(:each) do
      FileUtils.rm_rf(temp_dir)
    end

    it 'should skip configs without producer_class' do
      Karafka::App.routes.redraw do
        topic 'no-producer-topic' do
          active false
          schema 'sample.v1.SampleMessage'
          namespace 'sample.v1'
          key_config field: 'str'
          schema_backend :proto_schema_registry
        end
      end

      Rake::Task['deimos:generate_key_protos'].invoke

      # No files should be written since there's no producer_class
      expect(Dir.glob("#{temp_dir}/**/*.proto")).to be_empty
    end

    it 'should skip non-protobuf backends' do
      producer_class = Class.new(Deimos::Producer)
      stub_const('AvroProducer', producer_class)

      Karafka::App.routes.redraw do
        topic 'avro-topic' do
          active false
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config field: 'test_id'
          producer_class AvroProducer
        end
      end

      Rake::Task['deimos:generate_key_protos'].invoke

      # No files should be written for non-protobuf backends
      expect(Dir.glob("#{temp_dir}/**/*.proto")).to be_empty
    end

    it 'should skip configs without key_field' do
      producer_class = Class.new(Deimos::Producer)
      stub_const('NoKeyProducer', producer_class)

      Karafka::App.routes.redraw do
        topic 'no-key-topic' do
          active false
          schema 'sample.v1.SampleMessage'
          namespace 'sample.v1'
          key_config none: true
          producer_class NoKeyProducer
          schema_backend :proto_schema_registry
        end
      end

      Rake::Task['deimos:generate_key_protos'].invoke

      # No files should be written since there's no key_field
      expect(Dir.glob("#{temp_dir}/**/*.proto")).to be_empty
    end

    it 'should write key proto for protobuf topics with string key_field' do
      producer_class = Class.new(Deimos::Producer)
      stub_const('ProtoProducer', producer_class)

      Karafka::App.routes.redraw do
        topic 'proto-topic' do
          active false
          schema 'sample.v1.SampleMessage'
          namespace 'sample.v1'
          key_config field: 'str'
          producer_class ProtoProducer
          schema_backend :proto_schema_registry
        end
      end

      Rake::Task['deimos:generate_key_protos'].invoke

      # Verify the file was created with correct content
      proto_file = File.join(temp_dir, 'sample/v1/sample_message_key.proto')
      expect(File).to exist(proto_file)

      content = File.read(proto_file)
      expect(content).to include('syntax = "proto3";')
      expect(content).to include('package sample.v1;')
      expect(content).to include('message SampleMessageKey {')
      expect(content).to include('string str = 1;')
    end

    it 'should write key proto for protobuf topics with int32 key_field' do
      producer_class = Class.new(Deimos::Producer)
      stub_const('ProtoProducer', producer_class)

      Karafka::App.routes.redraw do
        topic 'proto-topic-int' do
          active false
          schema 'sample.v1.SampleMessage'
          namespace 'sample.v1'
          key_config field: 'num'
          producer_class ProtoProducer
          schema_backend :proto_schema_registry
        end
      end

      Rake::Task['deimos:generate_key_protos'].invoke

      proto_file = File.join(temp_dir, 'sample/v1/sample_message_key.proto')
      expect(File).to exist(proto_file)

      content = File.read(proto_file)
      expect(content).to include('syntax = "proto3";')
      expect(content).to include('package sample.v1;')
      expect(content).to include('message SampleMessageKey {')
      expect(content).to include('int32 num = 2;')
    end

    it 'should process multiple topics' do
      producer_class1 = Class.new(Deimos::Producer)
      producer_class2 = Class.new(Deimos::Producer)
      stub_const('ProtoProducer1', producer_class1)
      stub_const('ProtoProducer2', producer_class2)

      Karafka::App.routes.redraw do
        topic 'proto-topic-1' do
          active false
          schema 'sample.v1.SampleMessage'
          namespace 'sample.v1'
          key_config field: 'str'
          producer_class ProtoProducer1
          schema_backend :proto_schema_registry
        end
        topic 'proto-topic-2' do
          active false
          schema 'sample.v1.SampleMessage'
          namespace 'sample.v1'
          key_config field: 'num'
          producer_class ProtoProducer2
          schema_backend :proto_schema_registry
        end
      end

      Rake::Task['deimos:generate_key_protos'].invoke

      # Both topics use the same schema, so only one file is created
      # but it should be called twice (once per topic)
      proto_file = File.join(temp_dir, 'sample/v1/sample_message_key.proto')
      expect(File).to exist(proto_file)

      # The second topic overwrites the first, so we should see the 'num' field
      content = File.read(proto_file)
      expect(content).to include('message SampleMessageKey {')
      expect(content).to include('int32 num = 2;')
    end
  end
end
