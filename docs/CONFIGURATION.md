# Configuration

Deimos supports a succinct, readable syntax which uses
pure Ruby to allow flexible configuration.

You can access any configuration value via a simple `Deimos.config.whatever`.

Nested configuration is denoted in simple dot notation:
`kafka.ssl.enabled`. Headings below will follow the nested
configurations.

## Base Configuration
Config name|Default|Description
-----------|-------|-----------
logger|`Logger.new(STDOUT)`|The logger that Deimos will use.
phobos_logger|`Deimos.config.logger`|The logger passed to Phobos.
metrics|`Deimos::Metrics::Mock.new`|The metrics backend use for reporting.
tracer|`Deimos::Tracing::Mock.new`|The tracer backend used for debugging.

## Defining Producers

You can define a new producer thusly:
```ruby
Deimos.configure do
  producer do
    class_name 'MyProducer'
    topic 'MyTopic'
    schema 'MyTopicSchema'
    namespace 'my.namespace'
    key_config field: :id

  # If config.schema.path is app/schemas, assumes there is a file in
  # app/schemas/my/namespace/MyTopicSchema.avsc
  end
end
```

You can have as many `producer` blocks as you like to define more producers.

Config name|Default|Description
-----------|-------|-----------
class_name|nil|Class name of the producer class (subclass of `Deimos::Producer`.)
topic|nil|Topic to produce to.
schema|nil|Name of the schema to use to encode data before producing.
namespace|nil|Namespace of the schema to use when finding it locally.
key_config|nil|Configuration hash for message keys. See [Kafka Message Keys](../README.md#installation)
use_schema_classes|nil|Set to true or false to enable or disable using the producers schema classes. See [Generated Schema Classes](../README.md#generated-schema-classes)

## Defining Consumers

Consumers are defined almost identically to producers:

```ruby
Deimos.configure do
  consumer do
    class_name 'MyConsumer'
    topic 'MyTopic'
    schema 'MyTopicSchema'
    namespace 'my.namespace'
    key_config field: :id

    # Setting to :inline_batch will invoke consume_batch instead of consume
    # for each batch of messages.
    delivery :batch

  # If config.schema.path is app/schemas, assumes there is a file in
  # app/schemas/my/namespace/MyTopicSchema.avsc
  end
end
```

In addition to the producer configs, you can define a number of overrides
to the basic consumer configuration for each consumer. This is analogous to
the `listener` config in `phobos.yml`.

Config name|Default|Description
-----------|-------|-----------
class_name|nil|Class name of the consumer class (subclass of `Deimos::Consumer`.)
topic|nil|Topic to produce to.
schema|nil|This is optional but strongly recommended for testing purposes; this will validate against a local schema file used as the reader schema, as well as being able to write tests against this schema. This is recommended since it ensures you are always getting the values  you expect.
namespace|nil|Namespace of the schema to use when finding it locally.
key_config|nil|Configuration hash for message keys. See [Kafka Message Keys](../README.md#installation)
disabled|false|Set to true to skip starting an actual listener for this consumer on startup.
group_id|nil|ID of the consumer group.
use_schema_classes|nil|Set to true or false to enable or disable using the consumers schema classes. See [Generated Schema Classes](../README.md#generated-schema-classes)
max_concurrency|1|Number of threads created for this listener. Each thread will behave as an independent consumer. They don't share any state.
start_from_beginning|true|Once the consumer group has checkpointed its progress in the topic's partitions, the consumers will always start from the checkpointed offsets, regardless of config. As such, this setting only applies when the consumer initially starts consuming from a topic
max_bytes_per_partition|512.kilobytes|Maximum amount of data fetched from a single partition at a time.
min_bytes|1|Minimum number of bytes to read before returning messages from the server; if `max_wait_time` is reached, this is ignored.
max_wait_time|5|Maximum duration of time to wait before returning messages from the server, in seconds.
force_encoding|nil|Apply this encoding to the message payload. If blank it uses the original encoding. This property accepts values defined by the ruby Encoding class (https://ruby-doc.org/core-2.3.0/Encoding.html). Ex: UTF_8, ASCII_8BIT, etc.
delivery|`:batch`|The delivery mode for the consumer. Possible values: `:message, :batch, :inline_batch`. See Phobos documentation for more details.
session_timeout|300|Number of seconds after which, if a client hasn't contacted the Kafka cluster, it will be kicked out of the group.
offset_commit_interval|10|Interval between offset commits, in seconds.
offset_commit_threshold|0|Number of messages that can be processed before their offsets are committed. If zero, offset commits are not triggered by message processing
offset_retention_time|nil|The time period that committed offsets will be retained, in seconds. Defaults to the broker setting.
heartbeat_interval|10|Interval between heartbeats; must be less than the session window.
backoff|`(1000..60_000)`|Range representing the minimum and maximum number of milliseconds to back off after a consumer error.

## Defining Database Pollers

These are used when polling the database via `rake deimos:db_poller`. You
can create a number of pollers, one per topic.

```ruby
Deimos.configure do
  db_poller do
    producer_class 'MyProducer'
    run_every 2.minutes
  end
end
```

Config name|Default|Description
-----------|--|-----------
producer_class|nil|ActiveRecordProducer class to use for sending messages.
mode|:time_based|Whether to use time-based polling or state-based polling.
run_every|60|Amount of time in seconds to wait between runs.
timestamp_column|`:updated_at`|Name of the column to query. Remember to add an index to this column!
delay_time|2|Amount of time in seconds to wait before picking up records, to allow for transactions to finish.
retries|1|The number of times to retry for a *non-Kafka* error.
full_table|false|If set to true, do a full table dump to Kafka each run. Good for very small tables. Time-based only.
start_from_beginning|true|If false, start from the current time instead of the beginning of time if this is the first time running the poller. Time-based only.
state_column|nil|If set, this represents the DB column to use to update publishing status. State-based only.
publish_timestamp_column|nil|If set, this represents the DB column to use to update when publishing is done. State-based only.
published_state|nil|If set, the poller will update the `state_column` to this value when publishing succeeds. State-based only.
failed_state|nil|If set, the poller will update the `state_column` to this value when publishing fails. State-based only.

## Kafka Configuration

Config name|Default|Description
-----------|-------|-----------
kafka.logger|`Deimos.config.logger`|Logger passed to RubyKafka.
kafka.seed_brokers|`['localhost:9092']`|URL for the Kafka brokers.
kafka.client_id|`phobos`|Identifier for this application.
kafka.connect_timeout|15|The socket timeout for connecting to the broker, in seconds.
kafka.socket_timeout|15|The socket timeout for reading and writing to the broker, in seconds.
kafka.ssl.enabled|false|Whether SSL is enabled on the brokers.
kafka.ssl.ca_certs_from_system|false|Use CA certs from system.
kafka.ssl.ca_cert|nil| A PEM encoded CA cert, a file path to the cert, or an Array of certs to use with an SSL connection.
kafka.ssl.client_cert|nil|A PEM encoded client cert to use with an SSL connection, or a file path to the cert.
kafka.ssl.client_cert_key|nil|A PEM encoded client cert key to use with an SSL connection.
kafka.sasl.enabled|false|Whether SASL is enabled on the brokers.
kafka.sasl.gssapi_principal|nil|A KRB5 principal.
kafka.sasl.gssapi_keytab|nil|A KRB5 keytab filepath.
kafka.sasl.plain_authzid|nil|Plain authorization ID.
kafka.sasl.plain_username|nil|Plain username.
kafka.sasl.plain_password|nil|Plain password.
kafka.sasl.scram_username|nil|SCRAM username.
kafka.sasl.scram_password|nil|SCRAM password.
kafka.sasl.scram_mechanism|nil|Scram mechanism, either "sha256" or "sha512".
kafka.sasl.enforce_ssl|nil|Whether to enforce SSL with SASL.
kafka.sasl.oauth_token_provider|nil|OAuthBearer Token Provider instance that implements method token. See {Sasl::OAuth#initialize}.

## Consumer Configuration

These are top-level configuration settings, but they can be overridden
by individual consumers.

Config name|Default|Description
-----------|-------|-----------
consumers.session_timeout|300|Number of seconds after which, if a client hasn't contacted the Kafka cluster, it will be kicked out of the group.
consumers.offset_commit_interval|10|Interval between offset commits, in seconds.
consumers.offset_commit_threshold|0|Number of messages that can be processed before their offsets are committed. If zero, offset commits are not triggered by message processing
consumers.heartbeat_interval|10|Interval between heartbeats; must be less than the session window.
consumers.backoff|`(1000..60_000)`|Range representing the minimum and maximum number of milliseconds to back off after a consumer error.
consumers.reraise_errors|false|Default behavior is to swallow uncaught exceptions and log to the metrics provider. Set this to true to instead raise all errors. Note that raising an error will ensure that the message cannot be processed - if there is a bad message which will always raise that error, your consumer will not be able to proceed past it and will be stuck forever until you fix your code. See also the `fatal_error` configuration. This is automatically set to true when using the `TestHelpers` module in RSpec.
consumers.report_lag|false|Whether to send the `consumer_lag` metric. This requires an extra thread per consumer.
consumers.fatal_error|`proc { false }`|Block taking an exception, payload and metadata and returning true if this should be considered a fatal error and false otherwise. E.g. you can use this to always fail if the database is available. Not needed if reraise_errors is set to true.

## Producer Configuration

Config name|Default|Description
-----------|-------|-----------
producers.ack_timeout|5|Number of seconds a broker can wait for replicas to acknowledge a write before responding with a timeout.
producers.required_acks|1|Number of replicas that must acknowledge a write, or `:all` if all in-sync replicas must acknowledge.
producers.max_retries|2|Number of retries that should be attempted before giving up sending messages to the cluster. Does not include the original attempt.
producers.retry_backoff|1|Number of seconds to wait between retries.
producers.max_buffer_size|10_000|Number of messages allowed in the buffer before new writes will raise `BufferOverflow` exceptions.
producers.max_buffer_bytesize|10_000_000|Maximum size of the buffer in bytes. Attempting to produce messages when the buffer reaches this size will result in `BufferOverflow` being raised.
producers.compression_codec|nil|Name of the compression codec to use, or nil if no compression should be performed. Valid codecs: `:snappy` and `:gzip`
producers.compression_threshold|1|Number of messages that needs to be in a message set before it should be compressed. Note that message sets are per-partition rather than per-topic or per-producer.
producers.max_queue_size|10_000|Maximum number of messages allowed in the queue. Only used for async_producer.
producers.delivery_threshold|0|If greater than zero, the number of buffered messages that will automatically trigger a delivery. Only used for async_producer.
producers.delivery_interval|0|if greater than zero, the number of seconds between automatic message deliveries. Only used for async_producer.
producers.persistent_connections|false|Set this to true to keep the producer connection between publish calls. This can speed up subsequent messages by around 30%, but it does mean that you need to manually call sync_producer_shutdown before exiting, similar to async_producer_shutdown.
producers.schema_namespace|nil|Default namespace for all producers. Can remain nil. Individual producers can override.
producers.topic_prefix|nil|Add a prefix to all topic names. This can be useful if you're using the same Kafka broker for different environments that are producing the same topics.
producers.disabled|false|Disable all actual message producing. Generally more useful to use the `disable_producers` method instead.
producers.backend|`:kafka_async`|Currently can be set to `:db`, `:kafka`, or `:kafka_async`. If using Kafka directly, a good pattern is to set to async in your user-facing app, and sync in your consumers or delayed workers.

## Schema Configuration

Config name|Default|Description
-----------|-------|-----------
schema.backend|`:mock`|Backend representing the schema encoder/decoder. You can see a full list [here](../lib/deimos/schema_backends).
schema.registry_url|`http://localhost:8081`|URL of the Confluent schema registry.
schema.user|nil|Basic auth user.
schema.password|nil|Basic auth password.
schema.path|nil|Local path to find your schemas.
schema.use_schema_classes|false|Set this to true to use generated schema classes in your application.
schema.generated_class_path|`app/lib/schema_classes`|Local path to generated schema classes.
schema.nest_child_schemas|false|Set to true to nest subschemas within the generated class for the parent schema.
schema.generate_namespace_folders|false|Set to true to generate folders for schemas matching the last part of the namespace.

## Database Producer Configuration

Config name|Default|Description
-----------|-------|-----------
db_producer.logger|`Deimos.config.logger`|Logger to use inside the DB producer.
db_producer.log_topics|`[]`|List of topics to print full messages for, or `:all` to print all topics. This can introduce slowdown since it needs to decode each message using the schema registry. 
db_producer.compact_topics|`[]`|List of topics to compact before sending, i.e. only send the last message with any given key in a batch. This is an optimization which mirrors what Kafka itself will do with compaction turned on but only within a single batch.  You can also specify `:all` to compact all topics.

## Configuration Syntax

Sample: 

```ruby
Deimos.configure do
  logger Logger.new(STDOUT)
  # Nested config field
  kafka.seed_brokers ['my.kafka.broker:9092']

  # Multiple nested config fields via block
  consumers do
    session_timeout 30
    offset_commit_interval 10
  end

  # Define a new producer
  producer do
    class_name 'MyProducer'
    topic 'MyTopic'
    schema 'MyTopicSchema'
    key_config field: :id
  end

  # Define another new producer
  producer do
    class_name 'AnotherProducer'
    topic 'AnotherTopic'
    schema 'AnotherSchema'
    key_config plain: true
  end

  # Define a consumer
  consumer do
    class_name 'MyConsumer'
    topic 'TopicToConsume'
    schema 'ConsumerSchema'
    key_config plain: true
    # include Phobos / RubyKafka configs
    start_from_beginning true
    heartbeat_interval 10 
  end

end
```

Note that all blocks are evaluated in the context of the configuration object.
If you're calling this inside another class or method, you'll need to save
things you need to reference into local variables before calling `configure`.
