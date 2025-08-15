# Configuration

Deimos has two methods of configuration:

* Main Deimos configuration, which uses the [FigTree](https://github.com/flipp-oss/fig_tree) gem for its own settings.
* Karafka routing configuration, which adds extensions to existing [Karafka routes](https://karafka.io/docs/Routing/).

The majority of application configuration, including Kafka and `librdkafka` settings, are part of existing [Karafka configuration](https://karafka.io/docs/Configuration/).

## Main Configuration

You can access any configuration value via a simple `Deimos.config.whatever`.

Nested configuration is denoted in simple dot notation: `schema.path`. Headings below will follow the nested configurations.

### Configuration Syntax

Sample: 

```ruby
Deimos.configure do
  metrics { Deimos::Metrics::Datadog.new({host: 'localhost'}) }
  schema.path "#{Rails.root}/app/schemas"
  
  # Multiple nested config fields via block
  consumers do
    session_timeout 30
    offset_commit_interval 10
  end
end
```

### Base Configuration

| Config name | Default                     | Description                            |
|-------------|-----------------------------|----------------------------------------|
| metrics     | `Deimos::Metrics::Mock.new` | The metrics backend use for reporting. |
| tracer      | `Deimos::Tracing::Mock.new` | The tracer backend used for debugging. |

Note that all blocks are evaluated in the context of the configuration object.
If you're calling this inside another class or method, you'll need to save
things you need to reference into local variables before calling `configure`.

### Producer Configuration

| Config name                | Default        | Description                                                                                                                                                                                    |
|----------------------------|----------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| producers.topic_prefix     | nil            | Add a prefix to all topic names. This can be useful if you're using the same Kafka broker for different environments that are producing the same topics.                                       |
| producers.disabled         | false          | Disable all actual message producing. Generally more useful to use the `disable_producers` method instead.                                                                                     |
| producers.backend          | `:kafka_async` | Currently can be set to `:db`, `:kafka`, or `:kafka_async`. If using Kafka directly, a good pattern is to set to async in your user-facing app, and sync in your consumers or delayed workers. |
| producers.truncate_columns | false          | If set to true, will truncate values to their database limits when using KafkaSource.                                                                                                          |

### Schema Configuration

| Config name                 | Default                  | Description                                                                                                                                                |
|-----------------------------|--------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| schema.backend              | `:mock`                  | Backend representing the schema encoder/decoder. You can see a full list [here](../lib/deimos/schema_backends).                                            |
| schema.registry_url         | `http://localhost:8081`  | URL of the Confluent schema registry.                                                                                                                      |
| schema.user                 | nil                      | Basic auth user.                                                                                                                                           |
| schema.password             | nil                      | Basic auth password.                                                                                                                                       |
| schema.path                 | nil                      | Local path to find your schemas.                                                                                                                           |
| schema.paths                | {}                       | For multi-backend, this is a hash of backend names to a list of paths to associate. E.g. `{avro: ['app/schemas'], protobuf: ['protos', 'app/gen/protos']}` |
| schema.use_schema_classes   | false                    | Set this to true to use generated schema classes in your application.                                                                                      |
| schema.generated_class_path | `app/lib/schema_classes` | Local path to generated schema classes.                                                                                                                    |
| schema.nest_child_schemas   | false                    | Set to true to nest subschemas within the generated class for the parent schema.                                                                           |
| schema.use_full_namespace   | false                    | Set to true to generate folders for schemas matching the full namespace.                                                                                   |
| schema.schema_namespace_map | {}                       | A map of namespace prefixes to base module name(s). Example: { 'com.mycompany.suborg' => ['SchemaClasses'] }. Requires `use_full_namespace` to be true.    |

### Outbox Configuration

| Config name           | Default                | Description                                                                                                                                                                                                                                                                            |
|-----------------------|------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| outbox.logger         | `Deimos.config.logger` | Logger to use inside the DB producer.                                                                                                                                                                                                                                                  |
| outbox.log_topics     | `[]`                   | List of topics to print full messages for, or `:all` to print all topics. This can introduce slowdown since it needs to decode each message using the schema registry.                                                                                                                 |
| outbox.compact_topics | `[]`                   | List of topics to compact before sending, i.e. only send the last message with any given key in a batch. This is an optimization which mirrors what Kafka itself will do with compaction turned on but only within a single batch.  You can also specify `:all` to compact all topics. |

### Defining Database Pollers

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

| Config name              | Default      | Description                                                                                                                           |
|--------------------------|--------------|---------------------------------------------------------------------------------------------------------------------------------------|
| producer_class           | nil          | ActiveRecordProducer class to use for sending messages.                                                                               |
| producer_classes         | []           | Array of ActiveRecordProducer classes to use for sending messages. You can use this instead of `producer_class`.                      |
| mode                     | :time_based  | Whether to use time-based polling or state-based polling.                                                                             |
| run_every                | 60           | Amount of time in seconds to wait between runs.                                                                                       |
| timestamp_column         | `:updated_at` | Name of the column to query. Remember to add an index to this column!                                                                 |
| delay_time               | 2            | Amount of time in seconds to wait before picking up records, to allow for transactions to finish.                                     |
| retries                  | 1            | The number of times to retry for a *non-Kafka* error.                                                                                 |
| full_table               | false        | If set to true, do a full table dump to Kafka each run. Good for very small tables. Time-based only.                                  |
| start_from_beginning     | true         | If false, start from the current time instead of the beginning of time if this is the first time running the poller. Time-based only. |
| state_column             | nil          | If set, this represents the DB column to use to update publishing status. State-based only.                                           |
| publish_timestamp_column | nil          | If set, this represents the DB column to use to update when publishing is done. State-based only.                                     |
| published_state          | nil          | If set, the poller will update the `state_column` to this value when publishing succeeds. State-based only.                           |
| failed_state             | nil          | If set, the poller will update the `state_column` to this value when publishing fails. State-based only.                              |
| poller_class             | nil          | Poller subclass name to use for publishing to multiple kafka topics from a single poller.                                             |

## Karafka Routing

The following are additional settings that can be added to the `topic` block in Karafka routes, or to `defaults` blocks.

### Shared Settings

| Config name        | Default | Description                                                                                                                                                                                     |
|--------------------|---------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| payload_log        | :full   | Determines how much data is logged per payload.</br>`:full` - all keys and payloads are logged.</br>`:keys` - only keys are logged.</br>`:count` - only the total count of messages are logged. |
| schema             | nil     | Name of the schema to use to encode data before producing. For Avro, namespace and schema are separated, but protobuf uses only the fully resolved name including package.                      |
| namespace          | nil     | Namespace of the schema to use when finding it locally. Leave blank for protobuf.                                                                                                               |
| key_config         | nil     | Configuration hash for message keys. See [Kafka Message Keys](../README.md#kafka-message-keys).                                                                                                 |
| use_schema_classes | nil     | Set to true or false to enable or disable using the producers schema classes. See [Generated Schema Classes](../README.md#generated-schema-classes).                                            |

### Consumer Settings

| Config name              | Default           | Description                                                                                                                                                                                                                                                                                                                                                                                                                |
|--------------------------|-------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| each_message             | false             | If true, use `consume_message` for each message rather than `consume_batch` for the full batch.                                                                                                                                                                                                                                                                                                                            |
| reraise_errors           | false             | Default behavior is to swallow uncaught exceptions and log to the metrics provider. Set this to true to instead raise all errors. Note that raising an error will ensure that the message cannot be processed - if there is a bad message which will always raise that error, your consumer will not be able to proceed past it and will be stuck forever until you fix your code. See also the fatal_error configuration. |
| fatal_error              | `proc { false }`  | Block taking an exception, payload and metadata and returning true if this should be considered a fatal error and false otherwise. E.g. you can use this to always fail if the database is available. Not needed if reraise_errors is set to true.                                                                                                                                                                         |
| max_db_batch_size        | nil               | Maximum limit for batching database calls to reduce the load on the db.                                                                                                                                                                                                                                                                                                                                                    |
| bulk_import_id_column    | `:bulk_import_id` | Name of the column to use for multi-table imports.                                                                                                                                                                                                                                                                                                                                                                         |
| replace_associations     | true              | If false, append to associations in multi-table imports rather than replacing them.                                                                                                                                                                                                                                                                                                                                        |
| bulk_import_id_generator | nil               | Block to determine the bulk_import_id generated during bulk consumption. If no block is specified the provided/default block from the consumers configuration will be used.                                                                                                                                                                                                                                                |
| save_associations_first  | false             | Whether to save associated records of primary class prior to upserting primary records. Foreign key of associated records are assigned to the record class prior to saving the record class                                                                                                                                                                                                                                |

### Defining Consumers

An example consumer:
```ruby
Karafka::App.routes.draw do
  defaults do
    payload_log :keys
  end
  
  topic 'MyTopic' do
    namespace 'my-namespace'
    consumer MyConsumer
    schema 'MyTopicSchema'
    key_config field: :id

  # If config.schema.path is app/schemas, assumes there is a file in
  # app/schemas/my/namespace/MyTopicSchema.avsc
  end
end
```

### Producer Settings

| Config name    | Default | Description                                                                                                |
|----------------|---------|------------------------------------------------------------------------------------------------------------|
| producer_class | nil     | Class of the producer to use for the current topic.                                                        |
| disabled       | false   | Disable all actual message producing. Generally more useful to use the `disable_producers` method instead. |

## Defining Producers

You can define a new producer almost identically to consumers:
```ruby
Karafka::App.routes.draw do
  defaults do
    namespace 'my.namespace'
  end
  topic 'MyTopic' do
    producer_class MyProducer
    schema 'MyTopicSchema'
    key_config field: :id
    payload_log :count

  # If config.schema.path is app/schemas, assumes there is a file in
  # app/schemas/my/namespace/MyTopicSchema.avsc
  end
end
```

