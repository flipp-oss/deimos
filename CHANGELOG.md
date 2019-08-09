# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
