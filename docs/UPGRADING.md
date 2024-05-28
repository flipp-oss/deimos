# Upgrading Deimos

## Upgrading to 2.x

2.x is a major rewrite from 1.0.

- Changed deimos.encode_messsages to deimos.encode_message in Karafka monitor
- Note: generator needs to be run as KARAFKA_BOOT_FILE=false rails g deimos:v2
- Datadog metrics can now take `:karafka_namespace, :karafka_distribution_mode, :rd_kafka_metrics` tags to pass to MetricsListener
- Renamed :db backend to :outbox and :db_producer config to :outbox
- Renamed db_producer metrics to outbox
- Renamed db_producer task to outbox
- If a message fails to produce, the message itself can't be printed - still get metrics
- Some ActiveSupport notifications removed - use Karafka's
- Others are now prefixed by deimos.x
- Datadog metrics removed - use Karafka's (tracing is still the same)
- configs are moved to karafka.rb
- `payload_log` setting now works for batch consumer as well as producer
- No longer support `kafka_producer` for KafkaSource (need kafka_producers)
- Remove support for `record_attributes` that takes one argument
- key_config defaults to {none: true} instead of erroring out
- reraise_errors now defaults to true
- fatal_error? receives Karafka message array instead of payload
- removed BatchConsumer class
- removed deprecated configs
- no more backend=:test
- can no longer put schema/namespace on consumer/producer class
- payload_key no longer needed
- phobos.yml no longer supported
- remove test_consume_invalid_message and test_consume_batch_invalid_message
- Deprecate call_original and skip_expectation from test functions
- `batch` config instead of `delivery_method`
- Remove deprecated stub_producers_and_consumers!, stub_producer, stub_consumer, stub_batch_consumer
- You can publish messages without a Producer - Producer can be used for DB backends, method for partition key, disabling
- test_consume_message with a handler with no topic no longer supported

FRK:
- Remove aliasing
- Remove kafkateria_url
- FlippRubyKafka.configure_datadog unless %w(test development).include?(Rails.env) in generated file

TODO: 
- documentation
- FRK updates
- Check message too large flows



Testing:
- config errors
- Override defaults (e.g. producers.namespace)



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
