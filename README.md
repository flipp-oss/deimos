<p align="center">
  <img src="support/deimos-with-name.png" title="Deimos logo"/>
  <br/>
  <img src="https://img.shields.io/circleci/build/github/flipp-oss/deimos.svg" alt="CircleCI"/>
  <a href="https://badge.fury.io/rb/deimos-ruby"><img src="https://badge.fury.io/rb/deimos-ruby.svg" alt="Gem Version" height="18"></a>
  <img src="https://img.shields.io/codeclimate/maintainability/flipp-oss/deimos.svg"/>
</p>

A Ruby framework for marrying Kafka, a schema definition like Avro, and/or ActiveRecord and provide
a useful toolbox of goodies for Ruby-based Kafka development.
Built on Phobos and hence Ruby-Kafka.

<!--ts-->
   * [Additional Documentation](#additional-documentation)
   * [Installation](#installation)
   * [Versioning](#versioning)
   * [Configuration](#configuration)
   * [Schemas](#schemas)
   * [Producers](#producers)
        * [Auto-added Fields](#auto-added-fields)
        * [Coerced Values](#coerced-values)
        * [Instrumentation](#instrumentation)
        * [Kafka Message Keys](#kafka-message-keys)
   * [Consumers](#consumers)
   * [Rails Integration](#rails-integration)
        * [Controller Mixin](#controller-mixin)
   * [Database Backend](#database-backend)
   * [Database Poller](#database-poller)
   * [Running Consumers](#running-consumers)
   * [Metrics](#metrics)
   * [Testing](#testing)
        * [Integration Test Helpers](#integration-test-helpers)
   * [Utilities](#utilities)
   * [Contributing](#contributing) 
<!--te-->

# Additional Documentation

Please see the following for further information not covered by this readme:

* [Architecture Design](docs/ARCHITECTURE.md)
* [Configuration Reference](docs/CONFIGURATION.md)
* [Database Backend Feature](docs/DATABASE_BACKEND.md)
* [Upgrading Deimos](docs/UPGRADING.md)
* [Contributing to Integration Tests](docs/INTEGRATION_TESTS.md)

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

For a full configuration reference, please see [the configuration docs ](docs/CONFIGURATION.md).

# Schemas

Deimos was originally written only supporting Avro encoding via a schema registry.
This has since been expanded to a plugin architecture allowing messages to be
encoded and decoded via any schema specification you wish. 

Currently we have the following possible schema backends:
* Avro Local (use pure Avro)
* Avro Schema Registry (use the Confluent Schema Registry)
* Avro Validation (validate using an Avro schema but leave decoded - this is useful
  for unit testing and development)
* Mock (no actual encoding/decoding).

Note that to use Avro-encoding, you must include the [avro_turf](https://github.com/dasch/avro_turf) gem in your
Gemfile.

Other possible schemas could include [Protobuf](https://developers.google.com/protocol-buffers), [JSONSchema](https://json-schema.org/), etc. Feel free to
contribute!

To create a new schema backend, please see the existing examples [here](lib/deimos/schema_backends).

# Producers

Producers will look like this:

```ruby
class MyProducer < Deimos::Producer

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
      # You may specify the topic here with self.publish(payload, topic: 'my-topic')
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
* `encode_messages` - sent when messages are being schema-encoded.
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
best practice for domain messages is to schema-encode message keys 
with a separate schema.

This enforced by requiring producers to define a `key_config` directive. If
any message comes in with a key, the producer will error out if `key_config` is
not defined.

There are three possible configurations to use:

* `key_config none: true` - this indicates that you are not using keys at all
  for this topic. This *must* be set if your messages won't have keys - either
  all your messages in a topic need to have a key, or they all need to have
  no key. This is a good choice for events that aren't keyed - you can still
  set a partition key.
* `key_config plain: true` - this indicates that you are not using an encoded
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
will be turned into a key that looks like `{ "test_id" => "123"}` and schema-encoded
before being sent to Kafka. 

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

  # Optionally overload this to consider a particular exception
  # "fatal" only for this consumer. This is considered in addition
  # to the global `fatal_error` configuration block. 
  def fatal_error?(exception, payload, metadata)
    exception.is_a?(MyBadError)
  end

  def consume(payload, metadata)
    # Same method as Phobos consumers.
    # payload is an schema-decoded hash.
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

Use `config.consumers.reraise_errors = false` to swallow errors. You
can use instrumentation to handle errors you receive. You can also
specify "fatal errors" either via global configuration (`config.fatal_error`)
or via overriding a method on an individual consumer (`def fatal_error`).

### Batch Consumption

Instead of consuming messages one at a time, consumers can receive a batch of
messages as an array and then process them together. This can improve
consumer throughput, depending on the use case. Batch consumers behave like
other consumers in regards to key and payload decoding, etc.

To enable batch consumption, ensure that the `delivery` property of your
consumer is set to `inline_batch`.

Batch consumers will invoke the `consume_batch` method instead of `consume`
as in this example:

```ruby
class MyBatchConsumer < Deimos::Consumer

  def consume_batch(payloads, metadata)
    # payloads is an array of schema-decoded hashes.
    # metadata is a hash that contains information like :keys, :topic, 
    # and :first_offset.
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
Deimos.config.producers.disabled = true
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

### Controller Mixin

Deimos comes with a mixin for `ActionController` which automatically encodes and decodes schema
payloads. There are some advantages to encoding your data in e.g. Avro rather than straight JSON,
particularly if your service is talking to another backend service rather than the front-end
browser:

* It enforces a contract between services. Solutions like [OpenAPI](https://swagger.io/specification/) 
  do this as well, but in order for the client to know the contract, usually some kind of code 
  generation has to happen. Using schemas ensures both sides know the contract without having to change code.
  In addition, OpenAPI is now a huge and confusing format, and using simpler schema formats
  can be beneficial.
* Using Avro or Protobuf ensures both forwards and backwards compatibility,
  which reduces the need for versioning since both sides can simply ignore fields they aren't aware
  of.
* Encoding and decoding using Avro or Protobuf is generally faster than straight JSON, and
  results in smaller payloads and therefore less network traffic.

To use the mixin, add the following to your `WhateverController`:

```ruby
class WhateverController < ApplicationController
  include Deimos::Utils::SchemaControllerMixin

  request_namespace 'my.namespace.requests'
  response_namespace 'my.namespace.responses'
  
  # Add a "schemas" line for all routes that should encode/decode schemas.
  # Default is to match the schema name to the route name.
  schemas :index
  # will look for: my.namespace.requests.Index.avsc
  #                my.namespace.responses.Index.avsc 
  
  # Can use mapping to change the schema but keep the namespaces,
  # i.e. use the same schema name across the two namespaces
  schemas create: 'CreateTopic'
  # will look for: my.namespace.requests.CreateTopic.avsc
  #                my.namespace.responses.CreateTopic.avsc 

  # If all routes use the default, you can add them all at once
  schemas :index, :show, :update

  # Different schemas can be specified as well
  schemas :index, :show, request: 'IndexRequest', response: 'IndexResponse'

  # To access the encoded data, use the `payload` helper method, and to render it back,
  # use the `render_schema` method.
  
  def index
    response = { 'response_id' => payload['request_id'] + 'hi mom' }
    render_schema(response)
  end
end
```

To make use of this feature, your requests and responses need to have the correct content type.
For Avro content, this is the `avro/binary` content type.

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

    config.producers.backend = :db

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
  record_class Widget

  # Optional override of the way to fetch records based on payload and
  # key. Default is to use the key to search the primary key of the table.
  # Only used in non-batch mode.
  def fetch_record(klass, payload, key)
    super
  end

  # Optional override on how to set primary key for new records. 
  # Default is to set the class's primary key to the message's decoded key. 
  # Only used in non-batch mode.
  def assign_key(record, payload, key)
    super
  end

  # Optional override of the default behavior, which is to call `destroy`
  # on the record - e.g. you can replace this with "archiving" the record
  # in some way. 
  # Only used in non-batch mode.
  def destroy_record(record)
    super
  end
 
  # Optional override to change the attributes of the record before they
  # are saved.
  def record_attributes(payload, key)
    super.merge(:some_field => 'some_value')
  end

  # Optional override to change the attributes used for identifying records
  def record_key(payload)
    super
  end

  # Optional override, returns true by default.
  # When this method returns true, a record corresponding to the message
  # is created/updated.
  # When this method returns false, message processing is skipped and a
  # corresponding record will NOT be created/updated.
  def process_message?(payload)
    super
  end
end
```

#### Generating Tables and Models

Deimos provides a generator that takes an existing schema and generates a 
database table based on its fields. By default, any complex sub-types (such as 
records or arrays) are turned into JSON (if supported) or string columns.

Before running this migration, you must first copy the schema into your repo
in the correct path (in the example above, you would need to have a file
`{SCHEMA_ROOT}/com/my-namespace/MySchema.avsc`).

To generate a model and migration, run the following:

    rails g deimos:active_record TABLE_NAME FULL_SCHEMA_NAME
    
Example:

    rails g deimos:active_record my_table com.my-namespace.MySchema
    
...would generate:

    db/migrate/1234_create_my_table.rb
    app/models/my_table.rb

#### Generating Tables, Models and Consumer classes from schema

Deimos provides a generator that takes an existing schema and generates a
database table based on its fields, updates the specified kafka configuration file,
and creates a consumer class.

Before running this migration, you must first copy the schema into your repo
in the correct path (in the example above, you would need to have a file
`{SCHEMA_ROOT}/com/my-namespace/MySchema.avsc`).

To generate a model and migration, run the following:

    rails g deimos:kafka_consumer TABLE_NAME FULL_SCHEMA_NAME TOPIC_NAME KAFKA_CONFIG_FILE_PATH

Example:

    rails g deimos:kafka_consumer bullwhip Bullwhip.JobStatus JoBStatusTopic config/initializers/flipp_ruby_kafka.rb

...would generate:

      create  db/migrate/20210416172258_create_bullwhip.rb
      create  app/models/bullwhip.rb
      create  app/lib/kafka/bullwhip_consumer.rb
      append  config/initializers/flipp_ruby_kafka.rb

#### Batch Consumers

Deimos also provides a batch consumption mode for `ActiveRecordConsumer` which
processes groups of messages at once using the ActiveRecord backend. 

Batch ActiveRecord consumers make use of the
[activerecord-import](https://github.com/zdennis/activerecord-import) to insert
or update multiple records in bulk SQL statements. This reduces processing
time at the cost of skipping ActiveRecord callbacks for individual records.
Deleted records (tombstones) are grouped into `delete_all` calls and thus also
skip `destroy` callbacks.

Batch consumption is used when the `delivery` setting for your consumer is set to `inline_batch`.

**Note**: Currently, batch consumption only supports only primary keys as identifiers out of the box. See
[the specs](spec/active_record_batch_consumer_spec.rb) for an example of how to use compound keys.

By default, batches will be compacted before processing, i.e. only the last
message for each unique key in a batch will actually be processed. To change
this behaviour, call `compacted false` inside of your consumer definition.

A sample batch consumer would look as follows:

```ruby
class MyConsumer < Deimos::ActiveRecordConsumer
  schema 'MySchema'
  key_config field: 'my_field'
  record_class Widget

  # Controls whether the batch is compacted before consuming.
  # If true, only the last message for each unique key in a batch will be
  # processed.
  # If false, messages will be grouped into "slices" of independent keys
  # and each slice will be imported separately.
  #
  # compacted false


  # Optional override of the default behavior, which is to call `delete_all`
  # on the associated records - e.g. you can replace this with setting a deleted
  # flag on the record. 
  def remove_records(records)
    super
  end
 
  # Optional override to change the attributes of the record before they
  # are saved.
  def record_attributes(payload, key)
    super.merge(:some_field => 'some_value')
  end
end
```

## Database Poller

Another method of fetching updates from the database to Kafka is by polling
the database (a process popularized by [Kafka Connect](https://docs.confluent.io/current/connect/index.html)).
Deimos provides a database poller, which allows you the same pattern but
with all the flexibility of real Ruby code, and the added advantage of having
a single consistent framework to talk to Kafka.

One of the disadvantages of polling the database is that it can't detect deletions.
You can get over this by configuring a mixin to send messages *only* on deletion,
and use the poller to handle all other updates. You can reuse the same producer
for both cases to handle joins, changes/mappings, business logic, etc.

To enable the poller, generate the migration:

```ruby
rails g deimos:db_poller
```

Run the migration:

```ruby
rails db:migrate
```

Add the following configuration:

```ruby
Deimos.configure do
  db_poller do
    producer_class 'MyProducer' # an ActiveRecordProducer
  end
  db_poller do
    producer_class 'MyOtherProducer'
    run_every 2.minutes
    delay 5.seconds # to allow for transactions to finish
    full_table true # if set, dump the entire table every run; use for small tables
  end
end
```

All the information around connecting and querying the database lives in the
producer itself, so you don't need to write any additional code. You can 
define one additional method on the producer:

```ruby
class MyProducer < Deimos::ActiveRecordProducer
  ...
  def poll_query(time_from:, time_to:, column_name:, min_id:)
    # Default is to use the timestamp `column_name` to find all records
    # between time_from and time_to, or records where `updated_at` is equal to
    # `time_from` but its ID is greater than `min_id`. This is called
    # successively as the DB is polled to ensure even if a batch ends in the
    # middle of a timestamp, we won't miss any records.
    # You can override or change this behavior if necessary.
  end
end
```

To run the DB poller:

    rake deimos:db_poller

Note that the DB poller creates one thread per configured poller, and is
currently designed *not* to be scaled out - i.e. it assumes you will only
have one process running at a time. If a particular poll takes longer than
the poll interval (i.e. interval is set at 1 minute but it takes 75 seconds)
the next poll will begin immediately following the first one completing.

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
  `config.consumers.report_lag` is set to true.
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
* `db_producer.insert` - the number of messages inserted into the database
  for publishing. Tagged with `topic:{topic_name}`
* `db_producer.process` - the number of DB messages processed. Note that this
  is *not* the same as the number of messages *published* if those messages
  are compacted. Tagged with `topic:{topic_name}`

### Configuring Metrics Providers

See the `metrics` field under [Configuration](CONFIGURATION.md).
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

Trace spans are used for when incoming messages are schema-decoded, and a 
separate span for message consume logic.

### Configuring Tracing Providers

See the `tracing` field under [Configuration](#configuration).
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

Deimos comes with a test helper class which sets the various backends
to mock versions, and provides useful methods for testing consumers.

In `spec_helper.rb`:
```ruby
RSpec.configure do |config|
  config.include Deimos::TestHelpers
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
# as the topic is configured in your Deimos configuration:
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
message = Deimos::Backends::Test.sent_messages[0]
expect(message).to eq({
  message: {'some-key' => 'some-value'},
  topic: 'my-topic',
  key: 'my-id'
})
```

There is also a helper method that will let you test if an existing schema
would be compatible with a new version of it. You can use this in your 
Ruby console but it would likely not be part of your RSpec test:

```ruby
require 'deimos/test_helpers'
# Can pass a file path, a string or a hash into this:
Deimos::TestHelpers.schemas_compatible?(schema1, schema2)
```

### Integration Test Helpers

When running integration tests, you'll want to override the default test helper settings:

```ruby
config.before(:each, :my_integration_metadata) do
  Deimos.configure do
    producers.backend :kafka
    schema.backend :avro_schema_registry
  end
end
```

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

Both payload and key will be schema-decoded as necessary according to the
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

## Utilities

You can use your configured schema backend directly if you want to
encode and decode payloads outside of the context of sending messages.

```ruby
backend = Deimos.schema_backend(schema: 'MySchema', namespace: 'com.my-namespace')
encoded = backend.encode(my_payload)
decoded = backend.decode(my_encoded_payload)
coerced = backend.coerce(my_payload) # coerce to correct types
backend.validate(my_payload) # throws an error if not valid
fields = backend.schema_fields # list of fields defined in the schema
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
