# frozen_string_literal: true

module Deimos
  module Utils
    # Overall functionality related to DB poller.
    module DbPoller
      # Begin the DB Poller process.
      # @return [void]
      def self.start!
        if Deimos.config.db_poller_objects.empty?
          raise('No pollers configured!')
        end

        pollers = Deimos.config.db_poller_objects.map do |poller_config|
          self.class_for_config(poller_config.mode).new(poller_config)
        end
        executor = Sigurd::Executor.new(pollers,
                                        sleep_seconds: 5,
                                        logger: Deimos.config.logger)
        signal_handler = Sigurd::SignalHandler.new(executor)
        signal_handler.run!
      end

      # @param config_name [Symbol]
      # @return [Class<Deimos::Utils::DbPoller>]
      def self.class_for_config(config_name)
        case config_name
        when :state_based
          Deimos::Utils::DbPoller::StateBased
        else
          Deimos::Utils::DbPoller::TimeBased
        end
      end

      PollStatus = Struct.new(:batches_processed, :batches_errored, :messages_processed) do

        # @return [Integer]
        def current_batch
          batches_processed + 1
        end

        # @return [String]
        def report
          "#{batches_processed} batches, #{batches_errored} errored batches, #{messages_processed} processed messages"
        end
      end
    end
  end
end

require 'deimos/utils/db_poller/base'
require 'deimos/utils/db_poller/time_based'
require 'deimos/utils/db_poller/state_based'
