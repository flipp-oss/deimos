# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## UNRELEASED

- ### Roadmap :car:

- Generator for dumping data from kafka into database - Creates a migration, model and consumer class - Updates kafka configuration file

- ### Roadmap :car:

- Extracted the configuration piece into a separate gem, [fig_tree](https://www.github.com/flipp-oss/fig_tree).

- ### Fixes :wrench:

- Fixed a regression where the default values for consumer / Phobos listener configs were not correct (they were all nil). This is technically a breaking change, but it puts the configs back the way they were at version 1.4 and matches the documentation.

## 1.9.2 - 2021-01-29

- ### Fixes :wrench:

- Fix for `uninitialized constant ActiveSupport::Autoload` in certain circumstances
- Removed unnecessary monkey patch which was crashing on newer versions of ruby-kafka

## 1.9.0 - 2021-01-28

- ### Roadmap :car:

- Bumped the version of ruby-kafka to latest

- ### Fixes :wrench:

- Prevents DB Poller from reconnecting to DB if there is an open transaction
- Replaces `before` by `prepend_before` for more consistent test setups.
- Adds validation in the `kafka_producers` method (fixes [#90](https://github.com/flipp-oss/deimos/issues/90))

## 1.8.7 - 2021-01-14

- ### Roadmap :car:
- Update Phobos version to allow version 1.9 or 2.x.

## 1.8.6 - 2021-01-14

- ### Fixes :wrench:
- Fix for configuration bug with Ruby 3.0 (** instead of passing hash)

## 1.8.5 - 2021-01-13

- ### Fixes :wrench:
- Fixes for Rails 6.1 (remove usage of `update_attributes!`)

## 1.8.4 - 2020-12-02

### Features :star:
- Add overridable "process_message?" method to ActiveRecordConsumer to allow for skipping of saving/updating records

### Fixes :wrench:

- Do not apply type coercion to `timestamp-millis` and `timestamp-micros` logical types (fixes [#97](https://github.com/flipp-oss/deimos/issues/97))

## 1.8.3 - 2020-11-18

### Fixes :wrench:
- Do not resend already sent messages when splitting up batches
  (fixes [#24](https://github.com/flipp-oss/deimos/issues/24))
- KafkaSource crashing on bulk-imports if import hooks are disabled
  (fixes [#73](https://github.com/flipp-oss/deimos/issues/73))
- #96 Use string-safe encoding for partition keys
- Retry on offset seek failures in inline consumer
  (fixes [#5](Inline consumer should use retries when seeking))

## 1.8.2 - 2020-09-25

### Features :star:
- Add "disabled" config field to consumers to allow disabling
  individual consumers without having to comment out their
  entries and possibly affecting unit tests.

### Fixes :wrench:
- Prepend topic_prefix while encoding messages
  (fixes [#37](https://github.com/flipp-oss/deimos/issues/37))
- Raise error if producing without a topic
  (fixes [#50](https://github.com/flipp-oss/deimos/issues/50))
- Don't try to load producers/consumers when running rake tasks involving webpacker or assets

## 1.8.2-beta2 - 2020-09-15

### Features :star:

- Add details on using schema backend directly in README.
- Default to the provided schema if topic is not provided when
  encoding to `AvroSchemaRegistry`.
- Add mapping syntax for the `schema` call in `SchemaControllerMixin`.

## 1.8.2-beta1 - 2020-09-09

### Features :star:

- Added the ability to specify the topic for `publish`
and `publish_list` in a producer

## 1.8.1-beta9 - 2020-08-27

### Fixes :wrench:
- Moved the TestHelpers hook to `before(:suite)` to allow for
  overriding e.g. in integration tests.

## 1.8.1-beta7 - 2020-08-25

### Fixes :wrench:
- Fix for crash when sending pending metrics with DB producer.
- Fix for compacting messages if all the keys are already unique
  (fixes [#75](https://github.com/flipp-oss/deimos/issues/75))

## 1.8.1-beta6 - 2020-08-13

### Fixes :wrench:

- Fix for consuming nil payloads with Ruby 2.3.

## 1.8.1-beta5 - 2020-08-13

### Fixes :wrench:
- Fix regression bug which introduces backwards incompatibility
  with ActiveRecordProducer's `record_attributes` method.

## 1.8.1-beta4 - 2020-08-12

### Fixes :wrench:
- Fix regression bug where arrays were not being encoded

## 1.8.1-beta3 - 2020-08-05

### Fixes :wrench:
- Simplify decoding messages and handle producer not found
- Consolidate types in sub-records recursively
  (fixes [#72](https://github.com/flipp-oss/deimos/issues/72))

## 1.8.1-beta2 - 2020-07-28

### Features :star:
- Add `SchemaControllerMixin` to encode and decode schema-encoded
  payloads in Rails controllers.

## 1.8.1-beta1 - 2020-07-22

### Fixes :wrench:
- Retry deleting messages without resending the batch if the
  delete fails (fixes [#34](https://github.com/flipp-oss/deimos/issues/34))
- Delete messages in batches rather than all at once to
  cut down on the chance of a deadlock.

### Features :star:
- Add `last_processed_at` to `kafka_topic_info` to ensure
  that wait metrics are accurate in cases where records
  get created with an old `created_at` time (e.g. for
  long-running transactions).
- Add generator for ActiveRecord models and migrations (fixes [#6](https://github.com/flipp-oss/deimos/issues/6))

## 1.8.0-beta2 - 2020-07-08

### Fixes :wrench:
- Fix crash with batch consumption due to not having ActiveSupport::Concern

### Features :star:
- Add `first_offset` to the metadata sent via the batch

## 1.8.0-beta1 - 2020-07-06
### Features :star:
- Added `ActiveRecordConsumer` batch mode

### Fixes :wrench:
- Fixes `send_produce_error` to decode `failed_messages` with built-in decoder. 
- Lag calculation can be incorrect if no messages are being consumed.
- Fixed bug where printing messages on a MessageSizeTooLarge
  error didn't work.

### Roadmap
- Moved SignalHandler and Executor to the `sigurd` gem.

## 1.7.0-beta1 - 2020-05-12
### Features :star:
- Added the DB Poller feature / process.

## 1.6.4 - 2020-05-11
- Fixed the payload logging fix for errored messages as well.

## 1.6.3 - 2020-05-04
### Fixes :wrench:
- Fixed the payload logging fix.

## 1.6.2 - 2020-05-04
### Fixes :wrench:
- When saving records via `ActiveRecordConsumer`, update `updated_at` to today's time
  even if nothing else was saved.
- When logging payloads and metadata, decode them first.
- Fixes bug in `KafkaSource` that crashes when importing a mix of existing and new records with the `:on_duplicate_key_update` option.

## [1.6.1] - 2020-04-20
### Fixes :wrench:
- Re-consuming a message after crashing would try to re-decode message keys.

# [1.6.0] - 2020-03-05
### Roadmap :car:
- Removed `was_message_sent?` method from `TestHelpers`.

# [1.6.0-beta1] - 2020-02-05
### Roadmap :car:
- Updated dependency for Phobos to 1.9.0-beta3. This ensures compatibility with
  Phobos 2.0.
### Fixes :wrench:
- Fixed RSpec warning when using `test_consume_invalid_message`.

# [1.5.0-beta2] - 2020-01-17
### Roadmap :car:
- Added schema backends, which should simplify Avro encoding and make it
  more flexible for unit tests and local development.
### Features :star:
- Add `:test` producer backend which replaces the existing TestHelpers
  functionality of writing messages to an in-memory hash.

# [1.4.0-beta7] - 2019-12-16
### Fixes :wrench:
- Clone loggers when assigning to multiple levels.

# [1.4.0-beta6] - 2019-12-16
### Features :star:
- Added default for max_bytes_per_partition.

# [1.4.0-beta4] - 2019-11-26
### Features :star:
- Added `define_settings` to define settings without invoking callbacks.

# [1.4.0-beta2] - 2019-11-22
### Fixes :wrench:
- Settings with default_proc were being called immediately
  instead of being lazy-evaluated.

# [1.4.0-beta1] - 2019-11-22
### Roadmap :car:
- Complete revamp of configuration method.

# [1.3.0-beta5] - 2020-01-14
### Features :star:
- Added `db_producer.insert` and `db_producer.process` metrics.

# [1.3.0-beta4] - 2019-12-02
### Fixes :wrench:
- Fixed bug where by running `rake deimos:start` without
  specifying a producer backend would crash.

# [1.3.0-beta3] - 2019-11-26
### Fixes :wrench:
- Fixed bug in TestHelpers where key_decoder was not stubbed out.

# [1.3.0-beta2] - 2019-11-22
### Fixes :wrench:
- Fixed bug where consumers would require a key config in all cases
  even though it's optional if they don't use keys.

# [1.3.0-beta1] - 2019-11-21
### Features :star:
- Added `fetch_record` and `assign_key` methods to ActiveRecordConsumer.

# [1.2.0-beta1] - 2019-09-12
### Features :star:
- Added `fatal_error` to both global config and consumer classes.
- Changed `pending_db_messages_max_wait` metric to send per topic.
- Added config to compact messages in the DB producer.
- Added config to log messages in the DB producer.
- Added config to provide a separate logger to the DB producer.

# [1.1.0-beta2] - 2019-09-11
### Fixes :wrench:
- Fixed bug where ActiveRecordConsumer was not using `unscoped` to update
  via primary key and causing duplicate record errors.

# [1.1.0-beta1] - 2019-09-10
### Features :star:
- Added BatchConsumer.

## [1.0.0] - 2019-09-03
### Roadmap :car:
- Official release of Deimos 1.0!

## [1.0.0-beta26] - 2019-08-29
- Recover from Kafka::MessageSizeTooLarge in the DB producer.
- Shut down sync producers correctly when persistent_connections is true.
- Notify when messages fail to produce in the DB producer.
- Delete messages on failure and rely on notification.

## [1.0.0-beta25] - 2019-08-28
- Fix bug where crashing would cause producers to stay disabled

## [1.0.0-beta24] - 2019-08-26
- Reconnect DB backend if database goes away.
- Sleep only 5 seconds between attempts instead of using exponential backoff.
- Fix for null payload being Avro-encoded.

## [1.0.0-beta23] - 2019-08-22
- Fix bug where nil payloads were not being saved to the DB.
- Fix DB producer rake task looking at THREADS env var instead of THREAD_COUNT.
- Debug messages in the DB producer if debug logs are turned on.
- Changed logger in specs to info.

## [1.0.0-beta22] - 2019-08-09
- Add `pending_db_messages_max_wait` metric for the DB producer.
- Fix mock metrics to allow optional option hashes.

## [1.0.0-beta21] - 2019-08-08
- Handle Phobos `persistent_connections` setting in handling buffer overflows

## [1.0.0-beta20] - 2019-08-07
- Catch buffer overflows when producing via the DB producer and split the
  batch up.

## [1.0.0-beta19] - 2019-08-06
- Fix for DB producer crashing on error in Rails 3.

## [1.0.0-beta18] - 2019-08-02
- Fixed crash when sending metrics in a couple of places.

## [1.0.0-beta17] - 2019-07-31
- Added `rails deimos:db_producer` rake task.
- Fixed the DB producer so it runs inline instead of on a separate thread.
  Calling code should run it on a thread manually if that is the desired
  behavior.

## [1.0.0-beta15] - 2019-07-08
- Initial release.
