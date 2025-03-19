# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'logger' # https://stackoverflow.com/questions/79360526/uninitialized-constant-activesupportloggerthreadsafelevellogger-nameerror
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
require 'rspec/snapshot'
require 'karafka/testing/rspec/helpers'
require "trilogy_adapter/connection"
ActiveRecord::Base.public_send :extend, TrilogyAdapter::Connection
Dir['./spec/schemas/**/*.rb'].sort.each { |f| require f }

# Constants used for consumer specs
SCHEMA_CLASS_SETTINGS = { off: false, on: true }.freeze

class DeimosApp < Rails::Application
end
DeimosApp.initializer("setup_root_dir", before: "karafka.require_karafka_boot_file") do
  ENV['KARAFKA_ROOT_DIR'] = "#{Rails.root}/spec/karafka"
end
DeimosApp.initialize!

module Helpers

  def set_karafka_config(method, val)
    Deimos.karafka_configs.each { |c| c.send(method.to_sym, val) }
  end

  def register_consumer(klass, schema, namespace='com.my-namespace', key_config:{none: true}, configs: {})
    Karafka::App.routes.redraw do
      topic 'my-topic' do
        consumer klass
        schema schema
        namespace namespace
        key_config key_config
        configs.each do |k, v|
          public_send(k, v)
        end
      end
    end
  end
end

# Helpers for Executor/OutboxProducer
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
    { payload: payload, topic: topic, key: key}
  end

  DB_OPTIONS = [
    {
      adapter: 'postgresql',
      port: 5432,
      username: 'postgres',
      password: 'password',
      database: 'postgres',
      host: ENV['PG_HOST'] || 'localhost'
    },
    {
      adapter: 'trilogy',
      port: 3306,
      username: 'root',
      database: 'test',
      host: ENV['MYSQL_HOST'] || '127.0.0.1'
    },
    {
      adapter: 'trilogy',
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

        include_context('with DB')
        describe options[:adapter] do # rubocop:disable RSpec/EmptyExampleGroup
          self.instance_eval(&block)
        end
      end
    end
  end

  # :nodoc:
  def run_outbox_backend_migration
    migration_class_name = 'OutboxBackendMigration'
    migration_version = '[5.2]'
    migration = ERB.new(
      File.read('lib/generators/deimos/outbox_backend/templates/migration')
    ).result(binding)
    eval(migration) # rubocop:disable Security/Eval
    ActiveRecord::Migration.new.run(OutboxBackendMigration, direction: :up)
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
    run_outbox_backend_migration
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
  config.include Karafka::Testing::RSpec::Helpers

  config.include TestRunners
  config.include Helpers
  config.full_backtrace = true

  config.snapshot_dir = "spec/snapshots"

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
      deimos_config.producers.backend = :kafka
      deimos_config.schema.nest_child_schemas = true
      deimos_config.schema.path = File.join(File.expand_path(__dir__), 'schemas')
      deimos_config.consumers.reraise_errors = true
      deimos_config.schema.registry_url = ENV['SCHEMA_REGISTRY'] || 'http://localhost:8081'
      deimos_config.logger = Logger.new('/dev/null')
      deimos_config.logger.level = Logger::INFO
      deimos_config.schema.backend = :avro_validation
      deimos_config.schema.generated_class_path = 'spec/schemas'
    end
  end

  config.after(:each) do
    Deimos::EVENT_TYPES.each { |type| Karafka.monitor.notifications_bus.clear(type) }
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
      t.string(:publish_status)
      t.datetime(:published_at)
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

RSpec.shared_context('with widget_with_union_types') do
  before(:all) do
    ActiveRecord::Base.connection.create_table(:widget_with_union_types, force: true) do |t|
      t.string(:test_id)
      t.bigint(:test_long)
      t.json(:test_union_type)

      t.timestamps
    end

    # :nodoc:
    class WidgetWithUnionType < ActiveRecord::Base
      # @return [String]
      def generated_id
        'generated_id'
      end
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.drop_table(:widget_with_union_types)
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
    producer_class = Class.new(Deimos::Producer)
    stub_const('MyProducer', producer_class)

    producer_class_no_key = Class.new(Deimos::Producer)
    stub_const('MyNoKeyProducer', producer_class)

    Karafka::App.routes.redraw do
      topic 'my-topic-no-key' do
        schema 'MySchema'
        namespace 'com.my-namespace'
        key_config none: true
        producer_class producer_class_no_key
      end
      topic 'my-topic' do
        schema 'MySchema'
        namespace 'com.my-namespace'
        key_config field: 'test_id'
        producer_class producer_class
      end
    end

  end

  let(:messages) do
    (1..3).map do |i|
      build_message({ test_id: "foo#{i}", some_int: i }, 'my-topic', "foo#{i}")
    end
  end
end
