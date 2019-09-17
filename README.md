<p align="center">
  <img src="support/deimos-with-name.png" title="Deimos logo"/>
  <br/>
  <img src="https://img.shields.io/circleci/build/github/flipp-oss/deimos.svg" alt="CircleCI"/>
  <a href="https://badge.fury.io/rb/deimos-ruby"><img src="https://badge.fury.io/rb/deimos-ruby.svg" alt="Gem Version" height="18"></a>
  <img src="https://img.shields.io/codeclimate/maintainability/flipp-oss/deimos.svg"/>
</p>

A Ruby framework for marrying Kafka, Avro, and/or ActiveRecord and provide
a useful toolbox of goodies for Ruby-based Kafka development.
Built on Phobos and hence Ruby-Kafka.

<!--ts-->
   * [Installation](#installation)
   * [Versioning](#versioning)
   * [Configuration](#configuration)
   * [Producers](#producers)
        * [Auto-added Fields](#auto-added-fields)
        * [Coerced Values](#coerced-values)
        * [Instrumentation](#instrumentation)
        * [Kafka Message Keys](#kafka-message-keys)
   * [Consumers](#consumers)
   * [Rails Integration](#rails-integration)
   * [Database Backend](#database-backend)
   * [Running Consumers](#running-consumers)
   * [Metrics](#metrics)
   * [Testing](#testing)
        * [Integration Test Helpers](#integration-test-helpers)
   * [Contributing](#contributing) 
<!--te-->

# Installation

Add this line to your application's Gemfile:
```ruby
gem 'deimos-ruby'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install deimos-ruby

# Versioning

We use a version of semver for this gem. Any change in previous behavior 
(something works differently or something old no longer works)
is denoted with a bump in the minor version (0.4 -> 0.5). Patch versions 
are for bugfixes or new functionality which does not affect existing code. You
should be locking your Gemfile to the minor version:

```ruby
gem 'deimos-ruby', '~> 1.1'
```

# Configuration

To configure the gem, use `configure` in an initializer:

```ruby
Deimos.configure do |config|
  # Configure logger
  config.logger = Rails.logger

  # Phobos settings
  config.phobos_config_file = 'config/phobos.yml'
  config.schema_registry_url = 'https://my-schema-registry.com'
  config.seed_broker = 'my.seed.broker.0.net:9093,my.seed.broker.1.net:9093'
  config.ssl_enabled = ENV['KAFKA_SSL_ENABLED']
  if config.ssl_enabled
    config.ssl_ca_cert = File.read(ENV['SSL_CA_CERT'])
    config.ssl_client_cert = File.read(ENV['SSL_CLIENT_CERT'])
    config.ssl_client_cert_key = File.read(ENV['SSL_CLIENT_CERT_KEY'])
  end
  
  # Other settings

  # Local path to find schemas, for publishing and testing consumers
  config.schema_path = "#{Rails.root}/app/schemas"

  # Default namespace for producers to use
  config.producer_schema_namespace = 'com.deimos.my_app'
  
  # Prefix for all topics, e.g. environment name
  config.producer_topic_prefix = 'myenv.'
   
  # Disable all producers - e.g. when doing heavy data lifting and events
  # would be fired a different way
  config.disable_producers = true 
  
  # Default behavior is to swallow uncaught exceptions and log to DataDog.
  # Set this to true to instead raise all errors. Note that raising an error
  # will ensure that the message cannot be processed - if there is a bad
  # message which will always raise that error, your consumer will not
  # be able to proceed past it and will be stuck forever until you fix
  # your code.
  config.reraise_consumer_errors = true

  # Another way to handle errors is to set reraise_consumer_errors to false
  # but to set a global "fatal error" block that determines when to reraise:
  config.fatal_error do |exception, payload, metadata|
    exception.is_a?(BadError)
  end
  # Another example would be to check the database connection and fail
  # if the DB is down entirely.
  
  # Set to true to send consumer lag metrics
  config.report_lag = %w(production staging).include?(Rails.env)
  
  # Change the default backend. See Backends, below.
  config.backend = :db

  # Database Backend producer configuration
 
  # Logger for DB producer
  config.db_producer.logger = Logger.new('/db_producer.log')

  # List of topics to print full messages for, or :all to print all
  # topics. This can introduce slowdown since it needs to decode
  # each message using the schema registry. 
  config.db_producer.log_topics = ['topic1', 'topic2']

  # List of topics to compact before sending, i.e. only send the
  # last message with any given key in a batch. This is an optimization
  # which mirrors what Kafka itself will do with compaction turned on
  # but only within a single batch.  You can also specify :all to
  # compact all topics.
  config.db_producer.compact_topics = ['topic1', 'topic2']

  # Configure the metrics provider (see below).
  config.metrics = Deimos::Metrics::Mock.new({ tags: %w(env:prod my_tag:another_1) })

  # Configure the tracing provider (see below).
  config.tracer = Deimos::Tracing::Mock.new({service_name: 'my-service'})
end
```

Note that the configuration options from Phobos (seed_broker and the SSL settings)
can be removed from `phobos.yml` since Deimos will load them instead.

# Producers

Producers will look like this:

```ruby
class MyProducer < Deimos::Producer

  # Can override default namespace.
  namespace 'com.deimos.my-app-special'
  topic 'MyApp.MyTopic'
  schema 'MySchema'
  key_config field: 'my_field' # see Kafka Message Keys, below
  
  # If config.schema_path is app/schemas, assumes there is a file in
  # app/schemas/com/deimos/my-app-special/MySchema.avsc

  class << self
  
    # Optionally override the default partition key logic, which is to use
    # the payload key if it's provided, and nil if there is no payload key.
    def partition_key(payload)
      payload[:my_id]
    end
   
    # You can call publish / publish_list directly, or create new methods
    # wrapping them.
    
    def send_some_message(an_object)
      payload = {
        'some-key' => an_object.foo,
        'some-key2' => an_object.bar
      }
      # You can also publish an array with self.publish_list(payloads)
      self.publish(payload)
    end
    
  end
  
  
end
```

### Auto-added Fields

If your schema has a field called `message_id`, and the payload you give
your producer doesn't have this set, Deimos will auto-generate
a message ID. It is highly recommended to give all schemas a message_id
so that you can track each sent message via logging.

You can also provide a field in your schema called `timestamp` which will be 
auto-filled with the current timestamp if not provided.

### Coerced Values

Deimos will do some simple coercions if you pass values that don't
exactly match the schema.

* If the schema is :int or :long, any integer value, or a string representing
an integer, will be parsed to Integer.
* If the schema is :float or :double, any numeric value, or a string 
representing a number, will be parsed to Float.
* If the schema is :string, if the value implements its own `to_s` method,
this will be called on it. This includes hashes, symbols, numbers, dates, etc.

### Instrumentation

Deimos will send ActiveSupport Notifications. 
You can listen to these notifications e.g. as follows:

```ruby
  Deimos.subscribe('produce') do |event|
    # event is an ActiveSupport::Notifications::Event
    # you can access time, duration, and transaction_id
    # payload contains :producer, :topic, and :payloads
    data = event.payload
  end
``` 

The following events are produced (in addition to the ones already
produced by Phobos and RubyKafka):

* `produce_error` - sent when an error occurs when producing a message.
  * producer - the class that produced the message
  * topic
  * exception_object
  * payloads - the unencoded payloads
* `encode_messages` - sent when messages are being Avro-encoded.
  * producer - the class that produced the message
  * topic
  * payloads - the unencoded payloads
* `db_producer.produce` - sent when the DB producer sends messages for the
   DB backend. Messages that are too large will be caught with this
   notification - they will be deleted from the table and this notification
   will be fired with an exception object.
   * topic
   * exception_object
   * messages - the batch of messages (in the form of `Deimos::KafkaMessage`s)
     that failed - this should have only a single message in the batch.
  
Similarly: 
```ruby
  Deimos.subscribe('produce_error') do |event|	
    data = event.payloads 	
    Mail.send("Got an error #{event.exception_object.message} on topic #{data[:topic]} with payloads #{data[:payloads]}")	
  end	
      
  Deimos.subscribe('encode_messages') do |event|	
    # ... 
  end	
``` 

### Kafka Message Keys

Topics representing events rather than domain data don't need keys. However,
best practice for domain messages is to Avro-encode message keys 
with a separate Avro schema. 

This enforced by requiring producers to define a `key_config` directive. If
any message comes in with a key, the producer will error out if `key_config` is
not defined.

There are three possible configurations to use:

* `key_config none: true` - this indicates that you are not using keys at all
  for this topic. This *must* be set if your messages won't have keys - either
  all your messages in a topic need to have a key, or they all need to have
  no key. This is a good choice for events that aren't keyed - you can still
  set a partition key.
* `key_config plain: true` - this indicates that you are not using an Avro-encoded
  key. Use this for legacy topics - new topics should not use this setting.
* `key_config schema: 'MyKeySchema-key'` - this tells the producer to look for
  an existing key schema named `MyKeySchema-key` in the schema registry and to
  encode the key using it. Use this if you've already created a key schema
  or the key value does not exist in the existing payload 
  (e.g. it is a compound or generated key).
* `key_config field: 'my_field'` - this tells the producer to look for a field
  named `my_field` in the value schema. When a payload comes in, the producer
  will take that value from the payload and insert it in a *dynamically generated*
  key schema. This key schema does not need to live in your codebase. Instead,
  it will be a subset of the value schema with only the key field in it.

If your value schema looks like this:
```javascript
{
  "namespace": "com.my-namespace",
  "name": "MySchema",
  "type": "record",
  "doc": "Test schema",
  "fields": [
    {
      "name": "test_id",
      "type": "string",
      "doc": "test string"
    },
    {
      "name": "some_int",
      "type": "int",
      "doc": "test int"
    }
  ]
}
```

...setting `key_config field: 'test_id'` will create a key schema that looks
like this:

```javascript
{
  "namespace": "com.my-namespace",
  "name": "MySchema-key",
  "type": "record",
  "doc": "Key for com.my-namespace.MySchema",
  "fields": [
    {
      "name": "test_id",
      "type": "string",
      "doc": "test string"
    }
  ]
}
```

If you publish a payload `{ "test_id" => "123", "some_int" => 123 }`, this
will be turned into a key that looks like `{ "test_id" => "123"}` and encoded
via Avro before being sent to Kafka. 

If you are using `plain` or `schema` as your config, you will need to have a
special `payload_key` key to your payload hash. This will be extracted and
used as the key (for `plain`, it will be used directly, while for `schema`
it will be encoded first against the schema). So your payload would look like
`{ "test_id" => "123", "some_int" => 123, payload_key: "some_other_key"}`.
Remember that if you're using `schema`, the `payload_key` must be a *hash*,
not a plain value.

# Consumers

Here is a sample consumer:

```ruby
class MyConsumer < Deimos::Consumer

  # These are optional but strongly recommended for testing purposes; this
  # will validate against a local schema file used as the reader schema,
  # as well as being able to write tests against this schema.
  # This is recommended since it ensures you are always getting the values 
  # you expect.
  schema 'MySchema'
  namespace 'com.my-namespace'
  # This directive works identically to the producer - see Kafka Keys, above.
  # This only affects the `decode_key` method below. You need to provide
  # `schema` and `namespace`, above, for this to work.
  key_config field: :my_id 

  # Optionally overload this to consider a particular exception
  # "fatal" only for this consumer. This is considered in addition
  # to the global `fatal_error` configuration block. 
  def fatal_error?(exception, payload, metadata)
    exception.is_a?(MyBadError)
  end

  def consume(payload, metadata)
    # Same method as Phobos consumers.
    # payload is an Avro-decoded hash.
    # metadata is a hash that contains information like :key and :topic.
    # In general, your key should be included in the payload itself. However,
    # if you need to access it separately from the payload, you can use
    # metadata[:key]
  end
end
```

### Fatal Errors

The recommended configuration is for consumers *not* to raise errors
they encounter while consuming messages. Errors can be come from 
a variety of sources and it's possible that the message itself (or
what downstream systems are doing with it) is causing it. If you do
not continue on past this message, your consumer will essentially be
stuck forever unless you take manual action to skip the offset.

Use `config.reraise_consumer_errors = false` to swallow errors. You
can use instrumentation to handle errors you receive. You can also
specify "fatal errors" either via global configuration (`config.fatal_error`)
or via overriding a method on an individual consumer (`def fatal_error`).

### Batch Consumption

Instead of consuming messages one at a time, consumers can receive a batch of
messages as an array and then process them together. This can improve
consumer throughput, depending on the use case. Batch consumers behave like
other consumers in regards to key and payload decoding, etc.

To enable batch consumption, create a listener in `phobos.yml` and ensure that
the `delivery` property is set to `inline_batch`. For example:

```yaml
listeners:
  - handler: Consumers::MyBatchConsumer
    topic: my_batched_topic
    group_id: my_group_id
    delivery: inline_batch
```

Batch consumers must inherit from the Deimos::BatchConsumer class as in
this sample:

```ruby
class MyBatchConsumer < Deimos::BatchConsumer

  # See the Consumer sample in the previous section
  schema 'MySchema'
  namespace 'com.my-namespace'
  key_config field: :my_id 

  def consume_batch(payloads, metadata)
    # payloads is an array of Avro-decoded hashes.
    # metadata is a hash that contains information like :keys and :topic.
    # Keys are automatically decoded and available as an array with
    # the same cardinality as the payloads. If you need to iterate
    # over payloads and keys together, you can use something like this:
 
    payloads.zip(metadata[:keys]) do |_payload, _key|
      # Do something 
    end
  end
end
```

# Rails Integration

### Producing

Deimos comes with an ActiveRecordProducer. This takes a single or
list of ActiveRecord objects or hashes and maps it to the given schema.

An example would look like this:

```ruby
class MyProducer < Deimos::ActiveRecordProducer

  topic 'MyApp.MyTopic'
  schema 'MySchema'
  key_config field: 'my_field'
  
  # The record class should be set on every ActiveRecordProducer.
  # By default, if you give the producer a hash, it will re-fetch the
  # record itself for use in the payload generation. This can be useful
  # if you pass a list of hashes to the method e.g. as part of a 
  # mass import operation. You can turn off this behavior (e.g. if you're just
  # using the default functionality and don't need to override it) 
  # by setting `refetch` to false. This will avoid extra database fetches.
  record_class Widget, refetch: false

  # Optionally override this if you want the message to be 
  # sent even if fields that aren't in the schema are changed.
  def watched_attributes
    super + ['a_non_schema_attribute']
  end

  # If you want to just use the default functionality you can leave this
  # method out entirely. You only need to use it if you want to massage
  # the payload in some way, e.g. adding fields that don't exist on the
  # record itself.
  def generate_payload(attributes, record)
    super # generates payload based on the record and schema
  end
  
end

# or `send_event` with just one Widget
MyProducer.send_events([Widget.new(foo: 1), Widget.new(foo: 2)])
MyProducer.send_events([{foo: 1}, {foo: 2}])
```

#### Disabling Producers

You can disable producers globally or inside a block. Globally:
```ruby
Deimos.config.disable_producers = true
```

For the duration of a block:
```ruby
Deimos.disable_producers do
  # code goes here
end
```

For specific producers only:
```ruby
Deimos.disable_producers(Producer1, Producer2) do
  # code goes here
end
```

#### KafkaSource

There is a special mixin which can be added to any ActiveRecord class. This
will create callbacks which will automatically send messages to Kafka whenever
this class is saved. This even includes using the [activerecord-import](https://github.com/zdennis/activerecord-import) gem
to import objects (including using `on_duplicate_key_update`). However,
it will *not* work for `update_all`, `delete` or `delete_all`, and naturally
will not fire if using pure SQL or Arel.

Note that these messages are sent *during the transaction*, i.e. using
`after_create`, `after_update` and `after_destroy`. If there are
questions of consistency between the database and Kafka, it is recommended
to switch to using the DB backend (see next section) to avoid these issues.

When the object is destroyed, an empty payload with a payload key consisting of
the record's primary key is sent to the producer. If your topic's key is
from another field, you will need to override the `deletion_payload` method.

```ruby
class Widget < ActiveRecord::Base
  include Deimos::KafkaSource

  # Class method that defines an ActiveRecordProducer(s) to take the object
  # and turn it into a payload.
  def self.kafka_producers
    [MyProducer]
  end
  
  def deletion_payload
    { payload_key: self.uuid }
  end

  # Optional - indicate that you want to send messages when these events
  # occur.
  def self.kafka_config
    {
      :update => true,
      :delete => true,
      :import => true,
      :create => true
    }
  end
  
end
```

# Database Backend

Deimos provides a way to allow Kafka messages to be created inside a
database transaction, and send them asynchronously. This ensures that your
database transactions and Kafka messages related to those transactions 
are always in sync. Essentially, it separates the message logic so that a 
message is first validated, encoded, and saved in the database, and then sent
on a separate thread. This means if you have to roll back your transaction,
it also rolls back your Kafka messages.

This is also known as the [Transactional Outbox pattern](https://microservices.io/patterns/data/transactional-outbox.html).

To enable this, first generate the migration to create the relevant tables:

    rails g deimos:db_backend
    
You can now set the following configuration:

    config.publish_backend = :db

This will save all your Kafka messages to the `kafka_messages` table instead
of immediately sending to Kafka. Now, you just need to call

    Deimos.start_db_backend!
    
You can do this inside a thread or fork block.
If using Rails, you can use a Rake task to do this:

    rails deimos:db_producer
    
This creates one or more threads dedicated to scanning and publishing these 
messages by using the `kafka_topics` table in a manner similar to 
[Delayed Job](https://github.com/collectiveidea/delayed_job).
You can pass in a number of threads to the method:

    Deimos.start_db_backend!(thread_count: 2) # OR
    THREAD_COUNT=5 rails deimos:db_producer

If you want to force a message to send immediately, just call the `publish_list`
method with `force_send: true`. You can also pass `force_send` into any of the
other methods that publish events, like `send_event` in `ActiveRecordProducer`.

A couple of gotchas when using this feature:
* This may result in high throughput depending on your scale. If you're
  using Rails < 5.1, you should add a migration to change the `id` column
  to `BIGINT`. Rails >= 5.1 sets it to BIGINT by default.
* This table is high throughput but should generally be empty. Make sure
  you optimize/vacuum this table regularly to reclaim the disk space.
* Currently, threads allow you to scale the *number* of topics but not
  a single large topic with lots of messages. There is an [issue](https://github.com/flipp-oss/deimos/issues/23)
  opened that would help with this case.

For more information on how the database backend works and why it was 
implemented, please see [Database Backends](docs/DATABASE_BACKEND.md).

### Consuming

Deimos provides an ActiveRecordConsumer which will take a payload
and automatically save it to a provided model. It will take the intersection
of the payload fields and the model attributes, and either create a new record
or update an existing record. It will use the message key to find the record
in the database.

To delete a record, simply produce a message with the record's ID as the message
key and a null payload.

Note that to retrieve the key, you must specify the correct [key encoding](#kafka-message-keys)
configuration.

A sample consumer would look as follows:

```ruby
class MyConsumer < Deimos::ActiveRecordConsumer

  schema 'MySchema'
  key_config field: 'my_field'
  record_class Widget

  # Optional override of the default behavior, which is to call `destroy`
  # on the record - e.g. you can replace this with "archiving" the record
  # in some way. 
  def destroy_record(record)
    super
  end
 
  # Optional override to change the attributes of the record before they
  # are saved.
  def record_attributes(payload)
    super.merge(:some_field => 'some_value')
  end
end
```

#### Batch Consumers

Deimos also provides `ActiveRecordBatchConsumer`, which is similar to
`ActiveRecordConsumer` but inherits from `BatchConsumer` to process multiple
messages at once. 

Batch consumption makes use of the
[activerecord-import](https://github.com/zdennis/activerecord-import) to insert
or update multiple records in a single SQL statement. This reduces processing
time at the cost of skipping ActiveRecord callbacks for individual records.
Deleted records (tombstones) are grouped into `delete_all` calls and thus also
skip `destroy` callbacks.

A sample consumer would look as follows:

```ruby
class MyConsumer < Deimos::ActiveRecordBatchConsumer

  schema 'MySchema'
  key_config field: 'my_field'
  record_class Widget

  # Optional override of the default behavior, which is to call `delete_all`
  # on the associated records - e.g. you can replace this with setting a deleted
  # flag on the record. 
  def remove_records(records)
    super
  end
 
  # Optional override to change the attributes of the record before they
  # are saved.
  def record_attributes(payload)
    super.merge(:some_field => 'some_value')
  end
end
```

## Running consumers

Deimos includes a rake task. Once it's in your gemfile, just run

    rake deimos:start
    
This will automatically set an environment variable called `DEIMOS_RAKE_TASK`,
which can be useful if you want to figure out if you're inside the task
as opposed to running your Rails server or console. E.g. you could start your 
DB backend only when your rake task is running.

# Metrics

Deimos includes some metrics reporting out the box. It ships with DataDog support, but you can add custom metric providers as well.

The following metrics are reported:
* `consumer_lag` - for each partition, the number of messages
  it's behind the tail of the partition (a gauge). This is only sent if
  `config.report_lag` is set to true.
* `handler` - a count of the number of messages received. Tagged
  with the following:
    * `topic:{topic_name}`
    * `status:received`
    * `status:success`
    * `status:error`
    * `time:consume` (histogram)
        * Amount of time spent executing handler for each message
    * Batch Consumers - report counts by number of batches
        * `status:batch_received`
        * `status:batch_success`
        * `status:batch_error`
        * `time:consume_batch` (histogram)
            * Amount of time spent executing handler for entire batch
    * `time:time_delayed` (histogram)
        * Indicates the amount of time between the `timestamp` property of each
        payload (if present) and the time that the consumer started processing 
        the message.
* `publish` - a count of the number of messages received. Tagged
  with `topic:{topic_name}`
* `publish_error` - a count of the number of messages which failed
  to publish. Tagged with `topic:{topic_name}`
* `pending_db_messages_max_wait` - the number of seconds which the
  oldest KafkaMessage in the database has been waiting for, for use
  with the database backend. Tagged with the topic that is waiting.
  Will send a value of 0 with no topics tagged if there are no messages
  waiting.

### Configuring Metrics Providers

See the `# Configure Metrics Provider` section under [Configuration](#configuration)
View all available Metrics Providers [here](lib/deimos/metrics/metrics_providers)

### Custom Metrics Providers

Using the above configuration, it is possible to pass in any generic Metrics 
Provider class as long as it exposes the methods and definitions expected by 
the Metrics module.
The easiest way to do this is to inherit from the `Metrics::Provider` class 
and implement the methods in it.

See the [Mock provider](lib/deimos/metrics/mock.rb) as an example. It implements a constructor which receives config, plus the required metrics methods.

Also see [deimos.rb](lib/deimos.rb) under `Configure metrics` to see how the metrics module is called.

# Tracing

Deimos also includes some tracing for kafka consumers. It ships with 
DataDog support, but you can add custom tracing providers as well.

Trace spans are used for when incoming messages are avro decoded, and a 
separate span for message consume logic.

### Configuring Tracing Providers

See the `# Configure Tracing Provider` section under [Configuration](#configuration)
View all available Tracing Providers [here](lib/deimos/tracing)

### Custom Tracing Providers

Using the above configuration, it is possible to pass in any generic Tracing 
Provider class as long as it exposes the methods and definitions expected by
the Tracing module.
The easiest way to do this is to inherit from the `Tracing::Provider` class 
and implement the methods in it.

See the [Mock provider](lib/deimos/tracing/mock.rb) as an example. It implements a constructor which receives config, plus the required tracing methods.

Also see [deimos.rb](lib/deimos.rb) under `Configure tracing` to see how the tracing module is called.

# Testing

Deimos comes with a test helper class which automatically stubs out
external calls (like metrics and tracing providers and the schema 
registry) and provides useful methods for testing consumers.

In `spec_helper.rb`:
```ruby
RSpec.configure do |config|
  config.include Deimos::TestHelpers
  config.before(:each) do
    stub_producers_and_consumers!
  end
end
```

In your test, you now have the following methods available:
```ruby
# Pass a consumer class (not instance) to validate a payload against it.
# This will fail if the payload does not match the schema the consumer
# is set up to consume.
test_consume_message(MyConsumer, 
                    { 'some-payload' => 'some-value' }) do |payload, metadata|
      # do some expectation handling here
end

# You can also pass a topic name instead of the consumer class as long
# as the topic is configured in your phobos.yml configuration:
test_consume_message('my-topic-name',
                    { 'some-payload' => 'some-value' }) do |payload, metadata|
      # do some expectation handling here
end

# Alternatively, you can test the actual consume logic:
test_consume_message(MyConsumer, 
                    { 'some-payload' => 'some-value' }, 
                    call_original: true)
                    
# Test that a given payload is invalid against the schema:
test_consume_invalid_message(MyConsumer, 
                            { 'some-invalid-payload' => 'some-value' })
                            
# For batch consumers, there are similar methods such as:
test_consume_batch(MyBatchConsumer,
                   [{ 'some-payload' => 'some-value' },
                    { 'some-payload' => 'some-other-value' }]) do |payloads, metadata|
  # Expectations here
end

## Producing
                            
# A matcher which allows you to test that a message was sent on the given
# topic, without having to know which class produced it.                         
expect(topic_name).to have_sent(payload, key=nil)

# Inspect sent messages
message = Deimos::TestHelpers.sent_messages[0]
expect(message).to eq({
  message: {'some-key' => 'some-value'},
  topic: 'my-topic',
  key: 'my-id'
})
```

**Important note:** To use the `have_sent` helper, your producers need to be
loaded / required *before* starting the test. You can do this in your
`spec_helper` file, or if you are defining producers dynamically, you can
add an `RSpec.prepend_before(:each)` block where you define the producer.
Alternatively, you can use the `stub_producer` and `stub_consumer` methods
in your test.

There is also a helper method that will let you test if an existing schema
would be compatible with a new version of it. You can use this in your 
Ruby console but it would likely not be part of your RSpec test:

```ruby
require 'deimos/test_helpers'
# Can pass a file path, a string or a hash into this:
Deimos::TestHelpers.schemas_compatible?(schema1, schema2)
```

### Integration Test Helpers

You can use the `InlineConsumer` class to help with integration testing,
with a full external Kafka running.

If you have a consumer you want to test against messages in a Kafka topic,
use the `consume` method:
```ruby
Deimos::Utils::InlineConsumer.consume(
  topic: 'my-topic', 
  frk_consumer: MyConsumerClass,
  num_messages: 5
  )
```

This is a _synchronous_ call which will run the consumer against the 
last 5 messages in the topic. You can set `num_messages` to a number 
like `1_000_000` to always consume all the messages. Once the last 
message is retrieved, the process will wait 1 second to make sure 
they're all done, then continue execution.

If you just want to retrieve the contents of a topic, you can use
the `get_messages_for` method:

```ruby
Deimos::Utils::InlineConsumer.get_messages_for(
  topic: 'my-topic',
  schema: 'my-schema',
  namespace: 'my.namespace',
  key_config: { field: 'id' },
  num_messages: 5
)
```

This will run the process and simply return the last 5 messages on the
topic, as hashes, once it's done. The format of the messages will simply
be
```ruby
{
  payload: { key: value }, # payload hash here
  key: "some_value" # key value or hash here
}
```

Both payload and key will be Avro-decoded as necessary according to the
key config.

You can also just pass an existing producer or consumer class into the method,
and it will extract the necessary configuration from it:

```ruby
Deimos::Utils::InlineConsumer.get_messages_for(
  topic: 'my-topic',
  config_class: MyProducerClass,
  num_messages: 5
)
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/flipp-oss/deimos .

### Linting

Deimos uses Rubocop to lint the code. Please run Rubocop on your code 
before submitting a PR.

---
<p align="center">
  Sponsored by<br/>
  <a href="https://corp.flipp.com/">
    <img src="support/flipp-logo.png" title="Flipp logo" style="border:none;"/>
  </a>
</p>
