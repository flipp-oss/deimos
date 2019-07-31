# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0-beta17] - 2019-07-31
- Added `rails deimos:db_producer` rake task.
- Fixed the DB producer so it runs inline instead of on a separate thread.
  Calling code should run it on a thread manually if that is the desired
  behavior.

## [1.0.0-beta15] - 2019-07-08
- Initial release.
