# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'active_record'
require 'action_controller/railtie'
require 'database_cleaner'
require 'deimos'
require 'deimos/metrics/mock'
require 'deimos/tracing/mock'
require 'deimos/test_helpers'
require 'active_support/testing/time_helpers'
require 'activerecord-import'
require 'handlers/my_batch_consumer'
require 'handlers/my_consumer'
require 'rspec/rails'

class DeimosApp < Rails::Application
end
DeimosApp.initialize!

# Helpers for Executor/DbProducer
module TestRunners
  # Execute a block until it stops failing. This is helpful for testing threads
  # where we need to wait for them to continue but don't want to rely on
  # sleeping for X seconds, which is crazy brittle and slow.
  def wait_for
    start_time = Time.now
    begin
      yield
    rescue Exception # rubocop:disable Lint/RescueException
      raise if Time.now - start_time > 2 # 2 seconds is probably plenty of time! <_<

      sleep(0.1)
      retry
    end
  end

  # Test runner
  class TestRunner
    attr_accessor :id, :started, :stopped, :should_error

    # :nodoc:
    def initialize(id=nil)
      @id = id
    end

    # :nodoc:
    def start
      if @should_error
        @should_error = false
        raise 'OH NOES'
      end
      @started = true
    end

    # :nodoc:
    def stop
      @stopped = true
    end
  end
end

# :nodoc:
module DbConfigs
  # @param payload [Hash]
  # @param topic [String]
  # @param key [String]
  def build_message(payload, topic, key)
    message = Deimos::Message.new(payload, Deimos::Producer,
                                  topic: topic, key: key)
    message.encoded_payload = message.payload
    message.encoded_key = message.key
    message
  end

  DB_OPTIONS = [
    {
      adapter: 'postgresql',
      port: 5432,
      username: 'postgres',
      password: 'root',
      database: 'postgres',
      host: ENV['PG_HOST'] || 'localhost'
    },
    {
      adapter: 'mysql2',
      port: 3306,
      username: 'root',
      database: 'test',
      host: ENV['MYSQL_HOST'] || '127.0.0.1'
    },
    {
      adapter: 'sqlite3',
      database: 'test.sqlite3'
    } # this one always needs to be last for non-integration tests
  ].freeze

  # For each config, run some tests.
  def each_db_config(subject, &block)
    DB_OPTIONS.each do |options|
      describe subject, :integration, db_config: options do

        include_context 'with DB'
        describe options[:adapter] do # rubocop:disable RSpec/EmptyExampleGroup
          self.instance_eval(&block)
        end
      end
    end
  end

  # :nodoc:
  def run_db_backend_migration
    migration_class_name = 'DbBackendMigration'
    migration_version = '[5.2]'
    migration = ERB.new(
      File.read('lib/generators/deimos/db_backend/templates/migration')
    ).result(binding)
    eval(migration) # rubocop:disable Security/Eval
    ActiveRecord::Migration.new.run(DbBackendMigration, direction: :up)
  end

  # :nodoc:
  def run_db_poller_migration
    migration_class_name = 'DbPollerMigration'
    migration_version = '[5.2]'
    migration = ERB.new(
      File.read('lib/generators/deimos/db_poller/templates/migration')
    ).result(binding)
    eval(migration) # rubocop:disable Security/Eval
    ActiveRecord::Migration.new.run(DbPollerMigration, direction: :up)
  end

  # Set up the given database.
  def setup_db(options)
    ActiveRecord::Base.establish_connection(options)
    run_db_backend_migration
    run_db_poller_migration

    ActiveRecord::Base.descendants.each do |klass|
      klass.reset_sequence_name if klass.respond_to?(:reset_sequence_name)
      # reset internal variables - terrible hack to trick Rails into doing this
      table_name = klass.table_name
      klass.table_name = "#{table_name}2"
      klass.table_name = table_name
    end
  end
end

RSpec.configure do |config|
  config.extend(DbConfigs)
  include DbConfigs
  config.include TestRunners
  config.full_backtrace = true

  # true by default for RSpec 4.0
  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.filter_run(focus: true)
  config.run_all_when_everything_filtered = true

  config.before(:all) do
    Time.zone = 'Eastern Time (US & Canada)'
    ActiveRecord::Base.logger = Logger.new('/dev/null')
    ActiveRecord::Base.establish_connection(
      'adapter' => 'sqlite3',
      'database' => 'test.sqlite3'
    )
  end
  config.include Deimos::TestHelpers
  config.include ActiveSupport::Testing::TimeHelpers
  config.before(:suite) do
    setup_db(DbConfigs::DB_OPTIONS.last)

    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.mock_with(:rspec) do |mocks|
    mocks.yield_receiver_to_any_instance_implementation_blocks = true
    mocks.verify_partial_doubles = true
  end

  config.before(:each) do
    Deimos.config.reset!
    Deimos.configure do |deimos_config|
      deimos_config.producers.backend = :test
      deimos_config.phobos_config_file = File.join(File.dirname(__FILE__), 'phobos.yml')
      deimos_config.schema.path = File.join(File.expand_path(__dir__), 'schemas')
      deimos_config.consumers.reraise_errors = true
      deimos_config.schema.registry_url = ENV['SCHEMA_REGISTRY'] || 'http://localhost:8081'
      deimos_config.kafka.seed_brokers = ENV['KAFKA_SEED_BROKER'] || 'localhost:9092'
      deimos_config.logger = Logger.new('/dev/null')
      deimos_config.logger.level = Logger::INFO
      deimos_config.schema.backend = :avro_validation
    end
  end

  config.around(:each) do |example|
    use_cleaner = !example.metadata[:integration]

    DatabaseCleaner.start if use_cleaner

    example.run

    DatabaseCleaner.clean if use_cleaner
  end
end

RSpec.shared_context('with widgets') do
  before(:all) do
    ActiveRecord::Base.connection.create_table(:widgets, force: true) do |t|
      t.string(:test_id)
      t.integer(:some_int)
      t.boolean(:some_bool)
      t.timestamps
    end

    # :nodoc:
    class Widget < ActiveRecord::Base
      # @return [String]
      def generated_id
        'generated_id'
      end
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.drop_table(:widgets)
  end
end

RSpec.shared_context('with DB') do
  before(:all) do
    setup_db(self.class.metadata[:db_config] || DbConfigs::DB_OPTIONS.last)
  end

  after(:each) do
    Deimos::KafkaMessage.delete_all
    Deimos::KafkaTopicInfo.delete_all
  end
end

RSpec.shared_context('with publish_backend') do
  before(:each) do
    producer_class = Class.new(Deimos::Producer) do
      schema 'MySchema'
      namespace 'com.my-namespace'
      topic 'my-topic'
      key_config field: 'test_id'
    end
    stub_const('MyProducer', producer_class)

    producer_class = Class.new(Deimos::Producer) do
      schema 'MySchema'
      namespace 'com.my-namespace'
      topic 'my-topic'
      key_config none: true
    end
    stub_const('MyNoKeyProducer', producer_class)
  end

  let(:messages) do
    (1..3).map do |i|
      build_message({ foo: i }, 'my-topic', "foo#{i}")
    end
  end
end
