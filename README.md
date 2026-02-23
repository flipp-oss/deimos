<p align="center">
  <img src="support/deimos-with-name.png" title="Deimos logo"/>
  <br/>
  <img src="https://img.shields.io/circleci/build/github/flipp-oss/deimos.svg" alt="CircleCI"/>
  <a href="https://badge.fury.io/rb/deimos-ruby"><img src="https://badge.fury.io/rb/deimos-ruby.svg" alt="Gem Version" height="18"></a>
  <img src="https://img.shields.io/codeclimate/maintainability/flipp-oss/deimos.svg"/>
</p>

A Ruby framework for marrying Kafka, a schema definition like Avro, and/or ActiveRecord and provide
a useful toolbox of goodies for Ruby-based Kafka development.
Built on [Karafka](https://karafka.io/).

> [!IMPORTANT]  
> Deimos 2.x is a major rewrite from 1.x. Please see the [Upgrading Guide](./docs/UPGRADING.md) for information on the changes and how to upgrade.

Version 1.0 documentation can be found [here](https://github.com/flipp-oss/deimos/tree/v1).

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
        * [Producing](#rails-producing)
        * [Consuming](#rails-consuming)
        * [Generating Tables and Models](#generating-tables-and-models)
   * [Outbox Backend](#outbox-backend)
   * [Database Poller](#database-poller)
   * [Running Consumers](#running-consumers)
   * [Generated Schema Classes](#generated-schema-classes)
   * [Metrics](#metrics)
   * [Testing](#testing)
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
gem 'deimos-ruby', '~> 1.1.0'
```

# Configuration

For a full configuration reference, please see [the configuration docs ](docs/CONFIGURATION.md).

# Schemas

Deimos has a plugin architecture allowing messages to be encoded and decoded via any schema specification you wish. 

Currently we have the following possible schema backends:
* Avro Local (use pure Avro)
* Avro Schema Registry (use the Confluent Schema Registry)
* Avro Validation (validate using an Avro schema but leave decoded - this is useful
  for unit testing and development)
* Protobuf Local (use pure Protobuf)
* Protobuf Schema Registry (use Protobuf with the Confluent Schema Registry)
* Mock (no actual encoding/decoding).

Other possible schemas could include [JSONSchema](https://json-schema.org/), etc. Feel free to
contribute!

To create a new schema backend, please see the existing examples [here](lib/deimos/schema_backends).

# Producers

With the correct [configuration](./docs/CONFIGURATION.md), you do not need to use a Deimos producer class in order to send schema-encoded messages to Kafka. You can simply use `Karafka.producer.produce()` (see [here](https://karafka.io/docs/Producing-messages/)). There are a few features that Deimos producers provide:

* Using an instance method to determine partition key based on the provided payload
* Allowing global disabling of producers (or a particular producer class)
* Usage of the [Outbox](#outbox) producer backend.

Producer classes in general are a handy way to coerce some object into a hash or [schema class](#generated-schema-classes) that represents the payload.

A Deimos producer could look like this:

```ruby
class MyProducer < Deimos::Producer

  class << self
  
    # Optionally override the default partition key logic, which is to use
    # the payload key if it's provided, and nil if there is no payload key.
    def partition_key(payload)
      payload[:my_id]
    end
   
    # You can call produce directly, or create new methods wrapping it.
    
    def send_some_message(an_object)
      payload = {
        'some-key' => an_object.foo,
        'some-key2' => an_object.bar
      }
      self.produce([{payload: payload}])
      # additional keys can be added - see https://karafka.io/docs/WaterDrop-Usage/
      self.produce([{payload: payload, topic: "other-topic", key: "some-key", partition_key: "some-key2"}])
    end
  end
end
```

Note that if you are using Protobuf, you need to pass a Protobuf message object as the payload - you can't use a bare hash.

## Multiple clusters

If you have topics that are being routed to different clusters via Karafka configs, you can continue to make use of Deimos producers without having to instantiate the producer itself. Instead of calling `MyProducer.produce(message)`, you can call `Deimos.producer_for('MyTopic').produce(message)`.

Deimos will keep around one producer per broker server (i.e. `bootstrap.servers` config) that it sees on startup.

## Auto-added Fields

If your schema has a field called `message_id`, and the payload you give
your producer doesn't have this set, Deimos will auto-generate
a message ID. It is highly recommended to give all schemas a message_id
so that you can track each sent message via logging.

You can also provide a field in your schema called `timestamp` which will be 
auto-filled with the current timestamp if not provided.

## Coerced Values

Deimos will do some simple coercions if you pass values that don't
exactly match the schema.

* If the schema is :int or :long, any integer value, or a string representing
an integer, will be parsed to Integer.
* If the schema is :float or :double, any numeric value, or a string 
representing a number, will be parsed to Float.
* If the schema is :string, if the value implements its own `to_s` method,
this will be called on it. This includes hashes, symbols, numbers, dates, etc.

## Disabling Producers

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

## Kafka Message Keys

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
  "name": "MySchema_key",
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

If you are using `plain` or `schema` as your config, you can specify the key in two ways:

* Add a special `payload_key` key to your payload hash. This will be extracted and
used as the key (for `plain`, it will be used directly, while for `schema`
it will be encoded first against the schema). So your payload would look like
`{ "test_id" => "123", "some_int" => 123, payload_key: "some_other_key"}`.
Remember that if you're using `schema`, the `payload_key` must be a *hash*,
not a plain value.
* Specify `:message` and `:key` values when producing messages. This can be helpful when using [schema classes](#generated-schema-classes):

```ruby
MyProducer.publish({
                     message: MySchema.new("test_id" => "123", "some_int" => 123),
                     key: MySchemaKey.new("test_id" => "123")
                   })
```

### Protobuf and Key Schemas

> [!IMPORTANT]
> Protobuf should *not* be used as a key schema, since the binary encoding is [unstable](https://protobuf.dev/programming-guides/encoding/#implications) and may break partitioning. Deimos will automatically convert keys to sorted JSON, and will use JSON Schema in the schema registry.

To enable integration with [buf](https://buf.build/), Deimos provides a Rake task that will auto-generate `.proto` files. This task can be run in CI before running `buf push`. This way, downstream systems that want to use the generated key schemas can do so using their own tech stack.

    bundle exec rake deimos:generate_key_protos

## Instrumentation

Deimos will send events through the [Karafka instrumentation monitor](https://karafka.io/docs/Monitoring-and-Logging/#subscribing-to-the-instrumentation-events). 
You can listen to these notifications e.g. as follows:

```ruby
  Karafka.monitor.subscribe('deimos.encode_message') do |event|
    # event is a Karafka Event. You can use [] to access keys in the payload.
    messages = event[:messages]
  end
``` 

The following events are produced (in addition to the ones already
produced by Phobos and RubyKafka):

* `deimos.encode_message` - sent when messages are being schema-encoded.
  * producer - the class that produced the message
  * topic
  * payloads - the unencoded payloads
* `outbox.produce` - sent when the outbox producer sends messages for the
   outbox backend. Messages that are too large will be caught with this
   notification - they will be deleted from the table and this notification
   will be fired with an exception object.
   * topic
   * exception_object
   * messages - the batch of messages (in the form of `Deimos::KafkaMessage`s)
     that failed - this should have only a single message in the batch.
* `deimos.batch_consumption.valid_records` - sent when the consumer has successfully upserted records. Limited by `max_db_batch_size`.
  * consumer: class of the consumer that upserted these records
  * records: Records upserted into the DB (of type `ActiveRecord::Base`)
* `deimos.batch_consumption.invalid_records` - sent when the consumer has rejected records returned from `filtered_records`. Limited by `max_db_batch_size`.
  * consumer: class of the consumer that rejected these records
  * records: Rejected records (of type `Deimos::ActiveRecordConsume::BatchRecord`)
  
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

  def consume_batch
    # messages is a Karafka Messages - see https://github.com/karafka/karafka/blob/master/lib/karafka/messages/messages.rb
    messages.payloads.each do |payload|
      puts payload
    end
  end
end
```

## Fatal Errors

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

## Per-Message Consumption

Instead of consuming messages in a batch, consumers can process one message at a time. This is
helpful if the logic involved in each message is independent and you don't want to treat the whole
batch as a single unit.

To enable message consumption, ensure that the `each_message` property of your
consumer is set to `true`.

Per-message consumers will invoke the `consume_message` method instead of `consume_batch`
as in this example:

```ruby
class MyMessageConsumer < Deimos::Consumer

  def consume_message(message)
    # message is a Karafka Message object
    puts message.payload
  end
end
```

# Rails Integration

## <a name="rails-producing">Producing</a>

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
  
  # You can use a string here instead to avoid eager loading: record_class 'Widget'

  # Optionally override this if you want the message to be 
  # sent even if fields that aren't in the schema are changed.
  def watched_attributes(_record)
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

### KafkaSource

There is a special mixin which can be added to any ActiveRecord class. This
will create callbacks which will automatically send messages to Kafka whenever
this class is saved. This even includes using the [activerecord-import](https://github.com/zdennis/activerecord-import) gem
to import objects (including using `on_duplicate_key_update`). However,
it will *not* work for `update_all`, `delete` or `delete_all`, and naturally
will not fire if using pure SQL or Arel.

Note that these messages are sent *during the transaction*, i.e. using
`after_create`, `after_update` and `after_destroy`. If there are
questions of consistency between the database and Kafka, it is recommended
to switch to using the outbox backend (see next section) to avoid these issues.

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

## <a name="rails-consuming">Consuming</a>

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
  # or use a string: record_class 'Widget'

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
  
  # Optional override of the logic determining whether to delete the record. Default is to
  # delete it if the payload is nil.
  def delete_record?(record)
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

### Batch Consuming

Deimos also provides a batch consumption mode for `ActiveRecordConsumer` which
processes groups of messages at once using the ActiveRecord backend. 

Batch ActiveRecord consumers make use of
[activerecord-import](https://github.com/zdennis/activerecord-import) to insert
or update multiple records in bulk SQL statements. This reduces processing
time at the cost of skipping ActiveRecord callbacks for individual records.
Deleted records (tombstones) are grouped into `delete_all` calls and thus also
skip `destroy` callbacks.

Batch consumption is used when the `each_message` setting for your consumer is set to `false` (the default).

**Note**: Currently, batch consumption only supports only primary keys as identifiers out of the box. See
[the specs](spec/active_record_batch_consumer_spec.rb) for an example of how to use compound keys.

By default, batches will be compacted before processing, i.e. only the last
message for each unique key in a batch will actually be processed. To change
this behaviour, call `compacted false` inside of your consumer definition.

A sample batch consumer would look as follows:

```ruby
class MyConsumer < Deimos::ActiveRecordConsumer
  record_class Widget
  # or use a string: record_class 'Widget'

  # Controls whether the batch is compacted before consuming.
  # If true, only the last message for each unique key in a batch will be
  # processed.
  # If false, messages will be grouped into "slices" of independent keys
  # and each slice will be imported separately.
  #
  compacted false


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

### Saving data to Multiple Database tables

> This feature is implemented and tested with MySQL ONLY.

Sometimes, a Kafka message needs to be saved to multiple database tables. For example, if a `User` topic provides you metadata and profile image for users, we might want to save it to multiple tables: `User` and `Image`.

- Return associations as keys in `record_attributes` to enable this feature.
- The `bulk_import_id_column` config allows you to specify column_name on `record_class` which can be used to retrieve IDs after save. Defaults to `bulk_import_id`. This config is *required* if you have associations but optional if you do not.

You must override the `record_attributes` (and optionally `column` and `key_columns`) methods on your consumer class for this feature to work.
- `record_attributes` - This method is required to map Kafka messages to ActiveRecord model objects.
- `columns(klass)` - Should return an array of column names that should be used by ActiveRecord klass during SQL insert operation.
- `key_columns(messages, klass)` -  Should return an array of column name(s) that makes a row unique.

```ruby
class User < ApplicationRecord
  has_many :images
end

class MyConsumer < Deimos::ActiveRecordConsumer

  record_class User

  def record_attributes(payload, _key)
    {
      first_name: payload.first_name,
      images: [
                {
                  attr1: payload.image_url
                },
                {
                  attr2: payload.other_image_url
                }
              ]
    }
  end
  
  def key_columns(klass)
    case klass
    when User
      nil # use default
    when Image
      ["image_url", "image_name"]
    end
  end

  def columns(klass)
    case klass
    when User
      nil # use default
    when Image
      klass.columns.map(&:name) - [:created_at, :updated_at, :id]
    end
  end
end
```

## Generating Tables and Models

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

# Outbox Backend

Deimos provides a way to allow Kafka messages to be created inside a
database transaction, and send them asynchronously. This ensures that your
database transactions and Kafka messages related to those transactions 
are always in sync. Essentially, it separates the message logic so that a 
message is first validated, encoded, and saved in the database, and then sent
on a separate thread. This means if you have to roll back your transaction,
it also rolls back your Kafka messages.

This is also known as the [Transactional Outbox pattern](https://microservices.io/patterns/data/transactional-outbox.html).

To enable this, first generate the migration to create the relevant tables:

    rails g deimos:outbox
    
You can now set the following configuration:

    config.producers.backend = :outbox

This will save all your Kafka messages to the `kafka_messages` table instead
of immediately sending to Kafka. Now, you just need to call

    Deimos.start_outbox_backend!
    
You can do this inside a thread or fork block.
If using Rails, you can use a Rake task to do this:

    rails deimos:outbox
    
This creates one or more threads dedicated to scanning and publishing these 
messages by using the `kafka_topics` table in a manner similar to 
[Delayed Job](https://github.com/collectiveidea/delayed_job).
You can pass in a number of threads to the method:

    Deimos.start_outbox_backend!(thread_count: 2) # OR
    THREAD_COUNT=5 rails deimos:outbox

If you want to force a message to send immediately, just call the `produce`
method with `backend: kafka`.

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

# Database Poller

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
  # ...
  def poll_query(time_from:, time_to:, column_name:, min_id:)
    # Default is to use the timestamp `column_name` to find all records
    # between time_from and time_to, or records where `updated_at` is equal to
    # `time_from` but its ID is greater than `min_id`. This is called
    # successively as the DB is polled to ensure even if a batch ends in the
    # middle of a timestamp, we won't miss any records.
    # You can override or change this behavior if necessary.
  end

  # You can define this method if you need to do some extra actions with
  # the collection of elements you just sent to Kafka
  def post_process(batch)
    # write some code here
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

Note that the poller will retry infinitely if it encounters a Kafka-related error such
as a communication failure. For all other errors, it will retry once by default.

## State-based pollers

By default, pollers use timestamps and IDs to determine the records to publish. However, you can
set a different mode whereby it will include all records that match your query, and when done,
will update a state and/or timestamp column which should remove it from that query. With this
algorithm, you can ignore the `updated_at` and `id` columns.

To configure a state-based poller:

```ruby
db_poller do
  mode :state_based
  state_column :publish_state # the name of the column to update state to
  publish_timestamp_column :published_at # the column to update when publishing succeeds
  published_state 'published' # the value to put into the state_column when publishing succeeds
  failed_state 'publish_failed' the value to put into the state_column when publishing fails
end
```

# Running consumers

Deimos includes a rake task. Once it's in your gemfile, just run

    rake deimos:start
    
This will automatically set an environment variable called `DEIMOS_RAKE_TASK`,
which can be useful if you want to figure out if you're inside the task
as opposed to running your Rails server or console. E.g. you could start your 
DB backend only when your rake task is running.

# Generated Schema Classes

Deimos offers a way to generate classes from Avro schemas. These classes are documented
with YARD to aid in IDE auto-complete, and will help to move errors closer to the code.

Add the following configurations for schema class generation: 

```ruby
config.schema.generated_class_path 'path/to/generated/classes' # Defaults to 'app/lib/schema_classes'
```

Run the following command to generate schema classes in your application. It will generate classes for every configured consumer or producer by `Deimos.configure`:

    bundle exec rake deimos:generate_schema_classes

Add the following configurations to start using generated schema classes in your application's Consumers and Producers:

    config.schema.use_schema_classes true

Additionally, you can enable or disable the usage of schema classes for a particular consumer or producer with the
`use_schema_classes` config. See [Configuration](./docs/CONFIGURATION.md#defining-producers).

Note that if you have a schema in your repo but have not configured a producer or consumer, the generator will generate a schema class without a key schema.

One additional configuration option indicates whether nested records should be generated as top-level classes or would remain nested inside the generated class for its parent schema. The default is to nest them, as a flattened structure can have one sub-schema clobber another sub-schema defined in a different top-level schema.

    config.schema.nest_child_schemas = false # Flatten all classes into one directory

You can generate a tombstone message (with only a key and no value) by calling the `YourSchemaClass.tombstone(key)` method. If you're using a `:field` key config, you can pass in just the key scalar value. If using a key schema, you can pass it in as a hash or as another schema class.

## Consumer

The consumer interface uses the `decode_message` method to turn JSON hash into the Schemas
generated Class and provides it to the `consume`/`consume_batch` methods for their use.

Examples of consumers would look like this:
```ruby
class MyConsumer < Deimos::Consumer
  def consume_message(message)
    # Same method as before but message.payload is now an instance of Deimos::SchemaClass::Record
    # rather than a hash. 
    # You can interact with the schema class instance in the following way: 
    do_something(message.payload.test_id, message.payload.some_int)
    # The original behaviour was as follows:
    do_something(message.payload[:test_id], message.payload[:some_int])
  end
end
```

```ruby
class MyActiveRecordConsumer < Deimos::ActiveRecordConsumer
  record_class Widget
  # Any method that expects a message payload as a hash will instead
  # receive an instance of Deimos::SchemaClass::Record.
  def record_attributes(payload, key)
    # You can interact with the schema class instance in the following way:
    super.merge(:some_field => "some_value-#{payload.test_id}")
    # The original behaviour was as follows:
    super.merge(:some_field => "some_value-#{payload[:test_id]}")
  end
end
```

## Producer

Similarly to the consumer interface, the producer interface for using Schema Classes in your app
relies on the `produce` method to convert a _provided_ instance of a Schema Class
into a hash that can be used freely by the Kafka client.

Examples of producers would look like this:
```ruby
class MyProducer < Deimos::Producer
  class << self 
    # @param test_id [String]
    # @param some_int [Integer]
    def self.send_a_message(test_id, some_int)
      # Instead of sending in a Hash object to the publish or publish_list method,      
      # you can initialize an instance of your schema class and send that in.
      message = Schemas::MySchema.new(
        test_id: test_id,
        some_int: some_int
      )
      self.produce({payload: message})
    end
  end
end
```

```ruby
class MyActiveRecordProducer < Deimos::ActiveRecordProducer
  record_class Widget
  # @param attributes [Hash]
  # @param _record [Widget]
  # @return [Deimos::SchemaClass::Record]
  def self.generate_payload(attributes, _record)
    # This method converts your ActiveRecord into a Deimos::SchemaClass::Record. You will be able to use super
    # as an instance of Schemas::MySchema and set values that are not on your ActiveRecord schema.
    res = super
    res.some_value = "some_value-#{res.test_id}"
    res
  end
end
```

# Metrics

Deimos includes some metrics reporting out of the box. It adds to the existing [Karafka DataDog support](https://karafka.io/docs/Monitoring-and-Logging/#datadog-and-statsd-integration). It ships with DataDog support, but you can add custom metric providers as well.

The following metrics are reported:
* `deimos.pending_db_messages_max_wait` - the number of seconds which the
  oldest KafkaMessage in the database has been waiting for, for use
  with the database backend. Tagged with the topic that is waiting.
  Will send a value of 0 with no topics tagged if there are no messages
  waiting.
* `deimos.outbox.publish` - the number of messages inserted into the database
  for publishing. Tagged with `topic:{topic_name}`
* `deimos.outbox.process` - the number of DB messages processed. Note that this
  is *not* the same as the number of messages *published* if those messages
  are compacted. Tagged with `topic:{topic_name}`

## Configuring Metrics Providers

See the `metrics` field under [Configuration](#configuration).
View all available Metrics Providers [here](lib/deimos/metrics)

## Custom Metrics Providers

Using the above configuration, it is possible to pass in any generic Metrics 
Provider class as long as it exposes the methods and definitions expected by 
the Metrics module.
The easiest way to do this is to inherit from the `Metrics::Provider` class 
and implement the methods in it.

See the [Mock provider](lib/deimos/metrics/mock.rb) as an example. It implements a constructor which receives config, plus the required metrics methods.

Also see [deimos.rb](lib/deimos.rb) under `Configure metrics` to see how the metrics module is called.

# Tracing

Deimos also includes some tracing for kafka consumers. It ships with 
DataDog support, but you can add custom tracing providers as well. (It does not use the built-in Karafka
tracers so that it can support per-message tracing, which Karafka does not provide for.)

Trace spans are used for when incoming messages are schema-decoded, and a 
separate span for message consume logic.

## Configuring Tracing Providers

See the `tracing` field under [Configuration](#configuration).
View all available Tracing Providers [here](lib/deimos/tracing)

## Custom Tracing Providers

Using the above configuration, it is possible to pass in any generic Tracing 
Provider class as long as it exposes the methods and definitions expected by
the Tracing module.
The easiest way to do this is to inherit from the `Tracing::Provider` class 
and implement the methods in it.

See the [Mock provider](lib/deimos/tracing/mock.rb) as an example. It implements a constructor which receives config, plus the required tracing methods.

Also see [deimos.rb](lib/deimos.rb) under `Configure tracing` to see how the tracing module is called.

# Testing

Deimos comes with a test helper class which provides useful methods for testing consumers. This is built on top of
Karafka's [testing library](https://karafka.io/docs/Testing/) and is primarily helpful because it can decode
the sent messages for comparison (Karafka only decodes the messages once they have been consumed).

In `spec_helper.rb`:
```ruby
RSpec.configure do |config|
  config.include Deimos::TestHelpers
end
```

## Test Configuration

```ruby
# The following can be added to a rpsec file so that each unit 
# test can have the same settings every time it is run
after(:each) do
  Deimos.config.reset!
  # set specific settings here
  Deimos.config.schema.path = 'my/schema/path'
end

around(:each) do |ex|
  # replace e.g. avro_schema_registry with avro_validation, proto_schema_registry with proto_local
  Deimos::TestHelpers.with_mock_backends { ex.run }
end
```

With the help of these helper methods, RSpec examples can be written without having to tinker with Deimos settings.
This also prevents Deimos setting changes from leaking in to other examples. You can make these changes on an individual test level and ensure that it resets back to where it needs to go:
```ruby
    it 'should not fail this random test' do
      
      Deimos.configure do |config|
        config.consumers.fatal_error = proc { true }
      end
      ...
      expect(some_object).to be_truthy
    end
```

## Test Usage

You can use `karafka.produce()` and `consumer.consume` in your tests without having to go through
Deimos TestHelpers. However, there are some useful abilities that Deimos gives you:

```ruby
# Pass a consumer class (not instance) to validate a payload against it. This takes either a class
# or a topic (Karafka only supports topics in its test helpers). This will validate the payload
# and execute the consumer logic.
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

# For batch consumers, there are similar methods such as:
test_consume_batch(MyBatchConsumer,
                   [{ 'some-payload' => 'some-value' },
                    { 'some-payload' => 'some-other-value' }]) do |payloads, metadata|
  # Expectations here
end

## Producing
                            
# A matcher which allows you to test that a message was sent on the given
# topic, without having to know which class produced it.                         
expect(topic_name).to have_sent(payload, key=nil, partition_key=nil, headers=nil)

# You can use regular hash matching:
expect(topic_name).to have_sent({'some_key' => 'some-value', 'message_id' => anything})

# For Protobufs, default values are stripped from the hash so you need to use actual Protobuf
# objects:
expect(topic.name).to have_sent(MyMessage.new(some_key: 'some-value', message_id: 'my-message-id'))

# However, Protobufs don't allow RSpec-style matching, so you can at least do a 
# simple `include`-style matcher:

expect(topic.name).to have_sent_including(MyMessage.new(some_key: 'some-value'))

# Inspect sent messages
message = Deimos::TestHelpers.sent_messages[0]
expect(message).to eq({
  message: {'some-key' => 'some-value'},
  topic: 'my-topic',
  headers: { 'foo' => 'bar' },
  key: 'my-id'
})
```

# Utilities

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

You can also do an even more concise encode/decode:

```ruby
encoded = Deimos.encode(schema: 'MySchema', namespace: 'com.my-namespace', payload: my_payload)
decoded = Deimos.decode(schema: 'MySchema', namespace: 'com.my-namespace', payload: my_encoded_payload)
```

# Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/flipp-oss/deimos .

If making changes to the generator, you should regenerate the test schema classes by running `bundle exec ./regenerate_test_schema_classes.rb` .

You can regenerate test Protobuf classes by running:

    protoc -I spec/protos --ruby_out=spec/gen --ruby_opt=paths=source_relative spec/protos/**/*.proto

You can/should re-generate RBS types when methods or classes change by running the following:

    rbs collection install # if you haven't done it 
    rbs collection update
    bundle exec sord --hide-private --no-sord-comments sig/defs.rbs --tags 'override:Override'

## Linting

Deimos uses Rubocop to lint the code. Please run Rubocop on your code 
before submitting a PR. The GitHub CI will also run rubocop on your pull request. 

---
<p style="text-align: center">
  Sponsored by<br/>
  <a href="https://corp.flipp.com/">
    <img src="support/flipp-logo.png" title="Flipp logo" style="border:none;width:396px;display:block;margin-left:auto;margin-right:auto;" alt="Flipp logo"/>
  </a>
</p>
