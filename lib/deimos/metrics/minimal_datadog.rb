# frozen_string_literal: true

require 'deimos/metrics/provider'
require 'karafka/instrumentation/vendors/datadog/metrics_listener'
require 'waterdrop/instrumentation/vendors/datadog/metrics_listener'

module Deimos
  module Metrics
    # A Metrics wrapper class for Datadog, with only minimal metrics being sent. This will not
    # send any rdkafka metrics, and only the following:
    # * consumer_group
    # * error_occurred
    # * consumer.messages
    # * consumer.batches
    # * consumer.offset
    # * consumer.consumed.time_taken
    # * consumer.batch_size
    # * consumer.processing_lag
    # * consumer.consumption_lag
    class MinimalDatadog < Deimos::Metrics::Datadog

      def setup_karafka(config={})
        karafka_listener = MinimalDatadogListener.new do |karafka_config|
          karafka_config.client = @client
          if config[:karafka_namespace]
            karafka_config.namespace = config[:karafka_namespace]
          end
          if config[:karafka_distribution_mode]
            karafka_config.distribution_mode = config[:karafka_distribution_mode]
          end
          karafka_config.rd_kafka_metrics = []
        end
        Karafka.monitor.subscribe(karafka_listener)
      end

    end
  end
end
