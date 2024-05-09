# Upgrading Deimos

## Upgrading to 2.x

2.x is a major rewrite from 1.0.

- no more backend=:test
- payload_key no longer needed
- phobos.yml no longer supported
- remove test_consume_invalid_message and test_consume_batch_invalid_message
- Deprecate call_original and skip_expectation from test functions
- `batch` config instead of `delivery_method`
- Can/should we use avro_validation?
- Remove deprecated stub_producers_and_consumers!, stub_producer, stub_consumer, stub_batch_consumer
- You can publish messages without a Producer - Producer can be used for DB backends, method for partition key, disabling
- test_consume_message with a handler with no topic no longer supported

TODO: 

- Deimos defaults in Karafka routes instead of top-level
- Convert Phobos config values to Karafka
- Deimos configs to generate Karafka routes w/deprecation notice
- producer spec
- See if we can stop storing schema/namespace on consumers - `topic.deserializers[:payload].backend`
- 
- Logging and metrics via notifications
-   backends/base needs to work on Karafka messages
- Error messages: 
```
        if key.nil?
          return nil if config[:no_keys] # no key is fine, otherwise it's a problem

          raise 'No key given but a key is required! Use `key_config none: true` to avoid using keys.'
        end
        if config[:encode_key] && config[:key_field].nil? &&
           config[:key_schema].nil?
          raise 'No key config given - if you are not encoding keys, please use `key_config plain: true`'
        end
```
Need to add `Karafka.producer.middleware.append(Deimos::ProducerMiddleware)` somewhere


Testing:
- legacy mode
- Avro errors
- config errors
- with/without schema classes
- all key config combinations for both producer and consumer
- Override defaults (e.g. producers.namespace)

For producers:
* disabling producers
* DB backend
* partition_key via method


For middleware:
* topic prefix
* encoding, adding fields etc.


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
