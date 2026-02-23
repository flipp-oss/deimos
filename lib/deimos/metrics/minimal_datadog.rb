# frozen_string_literal: true

require 'deimos/metrics/provider'
require 'deimos/metrics/datadog'
require 'deimos/metrics/minimal_datadog_listener'

module Deimos
  module Metrics
    # A Metrics wrapper class for Datadog, with only minimal metrics being sent. This will only
    # send the following rdkafka metrics:
    # * consumer.lags
    # * consumer.lags_delta
    #
    # and only the following other metrics:
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
          karafka_config.rd_kafka_metrics = [
            Karafka::Instrumentation::Vendors::Datadog::MetricsListener::RdKafkaMetric.new(
              :gauge, :topics, 'consumer.lags', 'consumer_lag_stored'
            ),
            Karafka::Instrumentation::Vendors::Datadog::MetricsListener::RdKafkaMetric.new(
              :gauge, :topics, 'consumer.lags_delta', 'consumer_lag_stored_d'
            )
          ]
        end
        Karafka.monitor.subscribe(karafka_listener)
      end

    end
  end
end
