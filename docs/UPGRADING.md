# Upgrading Deimos

## Upgrading to 2.x

2.x is a major rewrite from 1.0. The underlying library has been changed from [Phobos](https://github.com/phobos/phobos) to [Karafka](https://karafka.io/). This change has given us an opportunity to fix some issues and deprecated code paths from version 1.0 as well as provide much more functionality by integrating more fully with the Karafka ecosystem.

For a deeper dive into the internal changes, please see [...]().

There are a number of breaking changes. We provide a `v2` generator to attempt to auto-fix many of these breaking changes automatically. To run the generator:

    KARAFKA_BOOT_FILE=false rails g deimos:v2

### Configuration

In V1, Deimos configuration was all done in a single `Deimos.configure` block, including Kafka configs, consumers and producers:

```ruby
Deimos.configure do
  producers.schema_namespace 'com.my-namespace'
  kafka.seed_brokers ['my-broker:9092']

  consumer do
    class_name 'MyConsumer'
    topic 'MyTopic'
    session_timeout 30
    schema 'MySchema'
    key_config field: :id
    namespace 'com.my-namespace'
  end

  producer do
    class_name 'MyProducer'
    topic 'MyTopic2'
    schema 'MySchema2'
    key_config none: true
  end
end  
```

In V2, the `Deimos.configure` block now only takes Deimos-specific settings, and is **not** used to configure producers and consumers. Kafka settings now go in the Karafka `kafka` setting method, and producers and consumers use Karafka [routing](https://karafka.io/docs/Routing/). There are Deimos-specific extensions to routing to apply to consumers and producers, either via a `defaults` block (applying to all consumers and producers) or in individual `topic` blocks:

```ruby
Deimos.configure do
  producers.schema_namespace 'com.my-namespace'
end

class KarafkaApp < Karafka::App
  setup do |config|
    config.kafka = {
      "bootstrap.servers": "my-broker:9092"
    }
  end
  
  routes.draw do
    defaults do
      namespace "com.my-namespace"
    end

    topic "MyTopic" do
      # Karafka settings
      consumer MyConsumer
      kafka({"session.timeout.ms": 30_000})
      # Deimos settings
      schema "MySchema" # the res
      key_config({field: id})
    end
    
    topic "MyTopic2" do
      # these are all Deimos settings since Karafka doesn't actually do per-topic producer configs
      producer_class MyProducer
      schema 'MySchema2'
      key_config none: true
    end
  end
end
```

This configuration must be in a file called `karafka.rb` at the root of your application. The V2 generator will generate this file for you. Without the generator, if you have this file and start up your app with the old `Deimos.configure` code, you will get notifications of the correct places to put these settings.


### Removed deprecations

The following were deprecated in version 1.x and are removed in 2.0.

* The `kafka_producer` method for KafkaSource is no longer supported. Please use `kafka_producers`. (This is not addressed by the V2 generator.)

```ruby
# before:
class MyRecord < ApplicationRecord
  def kafka_producer
    MyProducer
  end
end

# after:
class MyRecord < ApplicationRecord
  def kafka_producers
    [MyProducer]
  end
end
```

* The `record_attributes` method for ActiveRecordConsumer now must take two parameters, not one. (The V2 generator can fix this.)

```ruby
# before:
class MyConsumer < Deimos::ActiveRecordConsumer
  def record_attributes(payload)
    # ...
  end
end

# after:
class MyConsumer < Deimos::ActiveRecordConsumer
  def record_attributes(payload, key)
    # ...
  end
end
```

* The `BatchConsumer` class has been removed. Please use the `Consumer` class.
* You can no longer configure your application using a `phobos.yml` file. The V2 generator will not be able to work on apps using this approach.
* Removed `test_consume_invalid_message` and `test_consume_batch_invalid_message` test helpers. These did not serve a useful purpose.
* The following deprecated testing functions have been removed: `stub_producers_and_consumers!`, `stub_producer`, `stub_consumer`, `stub_batch_consumer`. These have not done anything in a long time.

### Major breaking changes
* Since Karafka only supports Ruby >= 3.0, that means Deimos also only supports those versions.
* Deimos no longer supports a separate logger from Karafka. When you configure a Karafka logger, Deimos will use that logger for all its logging. (Deimos logs will be prefixed with a `[Deimos]` tag.)
* The `:db` backend has been renamed to `:outbox`. All associated classes (like `DbProducer`) have likewise been renamed. The Rake task has also been renamed to `rake deimos:outbox`.
* The `SchemaControllerMixin` has been removed as there was no serious usage for it.
* `InlineConsumer` has been removed - Karafka Pro has an [Iterator API](https://karafka.io/docs/Pro-Iterator-API/) that does the same thing. There also has been no evidence that it was used (and was probably pretty buggy).
* The `:test` backend has been removed and the `Deimos::TestHelpers` module is now largely powered by [karafka-testing](https://github.com/karafka/karafka-testing/). This means that you can no longer use `Deimos::Backends::Test.sent_messages` - you need to use `Deimos::TestHelpers.sent_messages`.
* Individual consumer and producer settings now live within Karafka route configuration. This means you can no longer call e.g. `consumer.schema` to retrieve this information, as settings are no longer stored directly on the consumer and producer objects (it is still available, but via different methods).
* Consumers should no longer define a `consume` method, as the semantics have changed with Karafka. Instead, you can define a `consume_message` or `consume_batch` method. Both of these methods now take Karafka `Message` objects instead of hashes. The V2 generator can handle translating this for you, but if you create new consumers, you should take advantage of the Karafka functionality and use it first-class.
* Phobos `delivery_method` is no longer relevant. Instead, specify an `each_message` setting for your consumer. If set to true, you should define a `consume_message` method. Otherwise, you should define a `consume_batch` method. (Note that this is the reverse from the previous default, which assumed `delivery_method: message`.)

```ruby
# before:
class MyConsumer < Deimos::Consumer
  def consume(payload, metadata)
    # payload and metadata are both hashes
  end

  # OR with delivery_method: inline_batch
  def batch_consume(payloads, metadata)
    # payloads is an array of hashes, metadata is a hash
  end
end

# now:
class MyConsumer < Deimos::Consumer
  def consume_batch
    payloads = messages.payloads # messages is an instance method and `payloads` will return the decoded hashes
  end

  # OR with batch(false)
  def consume_message(message)
    # message is a Karafka Message object
    payload = message.payload
    key = message.key # etc.
  end
end
```

### Metrics

The following metrics have been **removed** in favor of Karafka's more robust [DataDog metrics](https://karafka.io/docs/Monitoring-and-Logging/#datadog-and-statsd-integration) and WaterDrop's [DataDog metrics](https://karafka.io/docs/WaterDrop-Monitoring-and-Logging/#datadog-and-statsd-integration):
* `consumer_lag` (use `consumer.lags`)
* `handler` (use `consumer.consumed.time_taken`)
* `publish` (use `produced_sync` and `produced_async`)
* `publish_error` (use `deliver.errors`)

You will need to manually add the DataDog MetricsListener as shown in the above pages.

The following metrics have been **renamed**:

* `db_producer.insert` -> `outbox.insert`
* `db_producer.process` -> `outbox.process`

### Instrumentation

Deimos's own instrumentation layer has been removed in favor of Karafka's. You can still subscribe to Deimos notifications - you simply do it via Karafka's monitor instead of Deimos's.

```ruby
# before:
Deimos.subscribe('encode_messages') do |event|	
    # ... 
end

# after:
Karafka.monitor.subscribe('deimos.encode_messages') do |event|
  # ...
end
```

Note that Karafka's monitors do not support the legacy "splatted" subscribe:
```ruby
Deimos.subscribe("event") do |*args|
  payload = ActiveSupport::Notifications::Event.new(*args).payload
end
```

The following instrumentation events have been **removed** in favor of Karafka's [events](https://karafka.io/docs/Monitoring-and-Logging/#subscribing-to-the-instrumentation-events):

* `produce_error` (use `error.occurred`)

The following events have been **renamed**:
* `encode_messages` -> `deimos.encode_message` (**note that only one message is instrumented at a time now**)
* `db_producer.produce` -> `deimos.outbox.produce`
* `batch_consumption.valid_records` -> `deimos.batch_consumption.valid_records`
* `batch_consumption.invalid_records` -> `deimos.batch_consumption.invalid_records`

### Additional breaking changes
* `key_config` now defaults to `{none: true}` instead of erroring out if not set.
* `fatal_error?` now receives a Karafka `messages` object instead of a payload hash or array of hashes.
* `watched_attributes` has been moved from the corresponding ActiveRecord class to the ActiveRecordProducer class. The object being watched is passed into the method.
* Removed `TestHelpers.full_integration_test!` and `kafka_test!` as Karafka does not currently support these use cases. If we need them back, we will need to put in changes to the testing library to support them.
* `test_consume_message` and `test_consume_batch` used to not fully validate schemas when using the `:avro_validation` backend. Now these are fully validated, which may cause test errors when upgrading.

### New functionality

* When setting up a Datadog metrics client, you can pass `:karafka_namespace`, `:karafka_distribution_mode`, or `:rd_kafka_metrics` tags to specify the Karafka settings for Datadog metrics.
- The `payload_log` setting now works for consumers as well as producers, as it is now a topic setting.
- You can publish messages **without a Deimos Producer class**. Karafka producers take a hash with `:message`, `:topic`, `:key`, `:headers` and `:partition_key` keys. As long as the topic is configured in `karafka.rb`, you don't need a special class to send the message. You can simply call `Karafka.producer.produce()`.
- The only features that are now available on the bare Producer (as opposed to ActiveRecordProducer) class are:
    - Outbox backend
    - Instance method to determine partition key (rather than passing it in)
    - Using `Deimos.disable_producers`
- If you need these features, you must continue using a `Deimos::Producer`.
- You can now call `.produce(messages)` directly on a `Deimos::Producer` which allows for use of these features while still passing a Karafka message hash. This removes the need to add a `payload_key` key into your payload. This is now the recommended method to use in a Deimos Producer.

### New deprecations
* For testing, you no longer have to call `unit_test!` to get the right settings. It is handled automatically by Karafka. The only thing this method now does is set the schema backend to `:avro_validation`, and you can do that in a single line.
* The `skip_expectation` and `call_original` arguments to `test_consume_message` and `test_consume_batch` have been deprecated and no longer need to be provided. The assumption is that `call_original` is always true.

## Upgrading from < 1.5.0 to >= 1.5.0

If you are using Confluent's schema registry to Avro-encode your
messages, you will need to manually include the `avro_turf` gem
in your Gemfile now.

This update changes how to interact with Deimos's schema classes.
Although these are meant to be internal, they are still "public"
and can be used by calling code.

Before 1.5.0:

```ruby
encoder = Deimos::AvroDataEncoder.new(schema: 'MySchema',
                                      namespace: 'com.my-namespace')
encoder.encode(my_payload)

decoder = Deimos::AvroDataDecoder.new(schema: 'MySchema',
                                      namespace: 'com.my-namespace')
decoder.decode(my_payload)
```

After 1.5.0:
```ruby
backend = Deimos.schema_backend(schema: 'MySchema', namespace: 'com.my-namespace')
backend.encode(my_payload)
backend.decode(my_payload)
```

The two classes are different and if you are using them to e.g.
inspect Avro schema fields, please look at the source code for the following:
* `Deimos::SchemaBackends::Base`
* `Deimos::SchemaBackends::AvroBase`
* `Deimos::SchemaBackends::AvroSchemaRegistry`

Deprecated `Deimos::TestHelpers.sent_messages` in favor of
`Deimos::Backends::Test.sent_messages`.

## Upgrading from < 1.4.0 to >= 1.4.0 

Previously, configuration was handled as follows:
* Kafka configuration, including listeners, lived in `phobos.yml`
* Additional Deimos configuration would live in an initializer, e.g. `kafka.rb`
* Producer and consumer configuration lived in each individual producer and consumer

As of 1.4.0, all configuration is centralized in one initializer
file, using default configuration.

Before 1.4.0:
```yaml
# config/phobos.yml
logger:
  file: log/phobos.log
  level: debug
  ruby_kafka:
    level: debug

kafka:
  client_id: phobos
  connect_timeout: 15
  socket_timeout: 15

producer:
  ack_timeout: 5
  required_acks: :all
  ...

listeners:
  - handler: ConsumerTest::MyConsumer
    topic: my_consume_topic
    group_id: my_group_id
  - handler: ConsumerTest::MyBatchConsumer
    topic: my_batch_consume_topic
    group_id: my_batch_group_id
    delivery: inline_batch
```

```ruby
# kafka.rb
Deimos.configure do |config|
  config.reraise_consumer_errors = true
  config.logger = Rails.logger
  ...
end

# my_consumer.rb
class ConsumerTest::MyConsumer < Deimos::Producer
  namespace 'com.my-namespace'
  schema 'MySchema'
  topic 'MyTopic'
  key_config field: :id
end
```

After 1.4.0:
```ruby
kafka.rb
Deimos.configure do
  logger Rails.logger
  kafka do
    client_id 'phobos'
    connect_timeout 15
    socket_timeout 15
  end
  producers.ack_timeout 5
  producers.required_acks :all
  ...
  consumer do
    class_name 'ConsumerTest::MyConsumer'
    topic 'my_consume_topic'
    group_id 'my_group_id' 
    namespace 'com.my-namespace'
    schema 'MySchema'
    topic 'MyTopic'
    key_config field: :id
  end
  ...
end
```

Note that the old configuration way *will* work if you set
`config.phobos_config_file = "config/phobos.yml"`. You will
get a number of deprecation notices, however. You can also still
set the topic, namespace, etc. on the producer/consumer class,
but it's much more convenient to centralize these configs
in one place to see what your app does.
