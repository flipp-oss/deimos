# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## UNRELEASED

# [1.4.0-beta3] - 2019-11-26
- Added `define_settings` to define settings without invoking callbacks.

# [1.4.0-beta2] - 2019-11-22
- FIX: settings with default_proc were being called immediately
  instead of being lazy-evaluated.

# [1.4.0-beta1] - 2019-11-22
- Complete revamp of configuration method.

# [1.3.0-beta2] - 2019-11-22
- Fixed bug where consumers would require a key config in all cases
  even though it's optional if they don't use keys.

# [1.3.0-beta1] - 2019-11-21
- Added `fetch_record` and `assign_key` methods to ActiveRecordConsumer.

# [1.2.0-beta1] - 2019-09-12
- Added `fatal_error` to both global config and consumer classes.
- Changed `pending_db_messages_max_wait` metric to send per topic.
- Added config to compact messages in the DB producer.
- Added config to log messages in the DB producer.
- Added config to provide a separate logger to the DB producer.

# [1.1.0-beta2] - 2019-09-11
- Fixed bug where ActiveRecordConsumer was not using `unscoped` to update
  via primary key and causing duplicate record errors.

# [1.1.0-beta1] - 2019-09-10
- Added BatchConsumer.

## [1.0.0] - 2019-09-03
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
