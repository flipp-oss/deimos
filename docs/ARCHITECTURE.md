# Deimos Architecture

Deimos is the third of three libraries that add functionality on top of each 
other:

* [RubyKafka](https://github.com/zendesk/ruby-kafka) is the low-level Kafka
  client, providing API's for producers, consumers and the client as a whole.
* [Phobos](https://github.com/phobos/phobos) is a lightweight wrapper on top
  of RubyKafka that provides threaded consumers, a simpler way to write
  producers, and lifecycle management.
* [Deimos](https://github.com/flipp-oss/deimos/) is a full-featured framework
  using Phobos as its base which provides schema integration (e.g. Avro), 
  database integration, metrics, tracing, test helpers and other utilities.
  
## Folder structure

As of May 12, 2020, the following are the important files to understand in how
Deimos fits together:
* `lib/generators`: Generators to generate database migrations, e.g.
   for the DB Poller and DB Producer features.
* `lib/tasks`: Rake tasks for starting consumers, DB Pollers, etc.
* `lib/deimos`: Main Deimos code.
* `lib/deimos/deimos.rb`: The bootstrap / startup code for Deimos. Also provides
   some global convenience methods and (for legacy purposes) the way to 
   start the DB Producer.
* `lib/deimos/backends`: The different plug-in producer backends - e.g. produce
   directly to Kafka, use the DB backend, etc.
* `lib/deimos/schema_backends`: The different plug-in schema handlers, such
  as the various flavors of Avro (with/without schema registry etc.)
* `lib/deimos/metrics`: The different plug-in metrics providers, e.g. Datadog.
* `lib/deimos/tracing`: The different plug-in tracing providers, e.g. Datadog.
* `lib/deimos/utils`: Utility classes for things not directly related to
   producing and consuming, such as the DB Poller, DB Producer, lag reporter, etc.
* `lib/deimos/config`: Classes related to configuring Deimos.
* `lib/deimos/monkey_patches`: Monkey patches to existing libraries. These
   should be removed in a future update.

## Features

### Producers and Consumers

Both producers and consumers include the `SharedConfig` module, which 
standardizes configuration like schema settings, topic, keys, etc.

Consumers come in two flavors: `Consumer` and `BatchConsumer`. Both include
`BaseConsumer` for shared functionality.

While producing messages go to Kafka by default, literally anything else
can happen when your producer calls `produce`, by swapping out the producer
_backend_. This is just a file that needs to inherit from `Deimos::Backends::Base`
and must implement a single method, `execute`.

Producers have a complex workflow while processing the payload to publish. This
is aided by the `Deimos::Message` class (not to be confused with the 
`KafkaMessage` class, which is an ActiveRecord used by the DB Producer feature,
below).

### Schemas

Schema backends are used to encode and decode payloads into different formats
such as Avro. These are integrated with producers and consumers, as well
as test helpers. These are a bit more involved than producer backends, and
must define methods such as:
* `encode` a payload or key (when encoding a key, for Avro a key schema
  may be auto-generated)
* `decode` a payload or key
* `validate` that a payload is correct for encoding
* `coerce` a payload into the given schema (e.g. turn ints into strings)
* Get a list of `schema_fields` in the configured schema, used when interacting
  with ActiveRecord
* Define a `mock` backend when the given backend is used. This is used
  during testing. Typically mock backends will validate values but not
  actually encode/decode them.
  
### Configuration

Deimos has its own `Configurable` module that makes heavy use of `method_missing`
to provide a very succinct but powerful configuration format (including
default values, procs, print out as hash, reset, etc.). It also
allows for multiple blocks to define different objects of the same time
(like producers, consumers, pollers etc.).

The configuration definition for Deimos is in `config/configuration.rb`. In
addition, there are methods in `config/phobos_config.rb` which translate to/from
the Phobos configuration format and support the old `phobos.yml` method
of configuration.

### Metrics and Tracing

These are simpler than other plugins and must implement the expected methods
(`increment`, `gauge`, `histogram` and `time` for metrics, and `start`, `finish`
and `set_error` for tracing). These are used primarily in producers and consumers.

### ActiveRecord Integration

Deimos provides an `ActiveRecordConsumer` and `ActiveRecordProducer`. These are
relatively lightweight ways to save data into a database or read it off 
the database as part of app logic. It uses things like the `coerce` method
of the schema backends to manage the differences between the given payload
and the configured schema for the topic.

### Database Backend / Database Producer

This feature (which provides better performance and transaction guarantees)
is powered by two components:
* The `db` _publish backend_, which saves messages to the database rather
  than to Kafka;
* The `DbProducer` utility, which runs as a separate process, pulls data
  from the database and sends it to Kafka.

There are a set of utility classes that power the producer, which are largely
copied from Phobos:
* `Executor` takes a set of "runnable" things (which implement a `start` and `stop`
  method) puts them in a thread pool and runs them all concurrently. It
  manages starting and stopping all threads when necessary.
* `SignalHandler` wraps the Executor and handles SIGINT and SIGTERM signals
  to stop the executor gracefully.
  
In the case of this feature, the `DbProducer` is the runnable object - it
can run several threads at once.

On the database side, the `ActiveRecord` models that power this feature are:
* `KafkaMessage`: The actual message, saved to the database. This message
  is already encoded by the producer, so only has to be sent.
* `KafkaTopicInfo`: Used for locking topics so only one producer can work
  on it at once.
  
A Rake task (defined in `deimos.rake`) can be used to start the producer.
  
### Database Poller

This feature (which periodically polls the database to send Kafka messages)
primarily uses other aspects of Deimos and hence is relatively small in size.
The `DbPoller` class acts as a "runnable" and is used by an Executor (above).
The `PollInfo` class is saved to the database to keep track of where each
poller is up to.

A Rake task (defined in `deimos.rake`) can be used to start the pollers.

### Other Utilities

The `utils` folder also contains the `LagReporter` (which sends metrics on
lag) and the `InlineConsumer`, which can read data from a topic and directly
pass it into a handler or save it to memory.
