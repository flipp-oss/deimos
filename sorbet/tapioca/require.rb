# typed: true
# frozen_string_literal: true

# Add your extra requires here (`bin/tapioca require` can be used to bootstrap this list)

require 'avro_turf'
require 'avro_turf/messaging'
require 'avro_turf/mutable_schema_store'
require 'datadog/statsd'
require 'erubi'
require 'ruby-kafka'
require 'action_mailer'
require 'active_record'
require 'sigurd'
require 'phobos'
require 'rack'
require 'rake'
require 'active_support/core_ext/uri'
require 'rails/generators'
require 'rails/generators/active_record/migration'
require 'fig_tree'
require 'active_support/notifications/instrumenter'
