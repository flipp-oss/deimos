# frozen_string_literal: true

require 'karafka/instrumentation/vendors/datadog/metrics_listener'
require 'waterdrop/instrumentation/vendors/datadog/metrics_listener'

module Deimos
  module Metrics
    class MinimalDatadogListener < ::Karafka::Instrumentation::Vendors::Datadog::MetricsListener
      # override existing listener so we don't emit metrics we don't care about
      def on_connection_listener_fetch_loop_received(_event)
      end

      def on_consumer_revoked(_event)
      end

      def on_consumer_shutdown(_event)
      end

      def on_consumer_ticked(_event)
      end

      def on_worker_process(_event)
      end

      def on_worker_processed(_event)
      end
    end
  end
end
