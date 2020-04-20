# frozen_string_literal: true

require 'deimos/poll_info'
require 'deimos/utils/executor'
require 'deimos/utils/signal_handler'

module Deimos
  module Utils
    # Class which continually polls the database and sends Kafka messages.
    class DbPoller
      BATCH_SIZE = 1000

      # Needed for Executor so it can identify the worker
      attr_reader :id

      # Begin the DB Poller process.
      def self.start!
        if Deimos.config.db_poller_objects.empty?
          raise('No pollers configured!')
        end

        pollers = Deimos.config.db_poller_objects.map do |poller_config|
          self.new(poller_config)
        end
        executor = Deimos::Utils::Executor.new(pollers,
                                               sleep_seconds: 5,
                                               logger: Deimos.config.logger)
        signal_handler = Deimos::Utils::SignalHandler.new(executor)
        signal_handler.run!
      end

      # @param config [Deimos::Configuration::ConfigStruct]
      def initialize(config)
        @config = config
        @id = SecureRandom.hex
        begin
          @producer = @config.producer_class.constantize
        rescue NameError
          raise "Class #{@config.producer_class} not found!"
        end
        unless @producer < Deimos::ActiveRecordProducer
          raise "Class #{@producer.class.name} is not an ActiveRecordProducer!"
        end
      end

      # Start the poll:
      # 1) Grab the current PollInfo from the database indicating the last
      # time we ran
      # 2) On a loop, process all the recent updates between the last time
      # we ran and now.
      def start
        Deimos.config.logger.info('Starting...')
        @signal_to_stop = false
        retrieve_poll_info
        loop do
          if @signal_to_stop
            Deimos.config.logger.info('Shutting down')
            break
          end
          process_updates
          sleep 0.1
        end
      end

      # Grab the PollInfo or create if it doesn't exist.
      def retrieve_poll_info
        ActiveRecord::Base.connection.reconnect!
        @info = Deimos::PollInfo.find_by_producer(@config.producer_class) ||
                Deimos::PollInfo.create!(producer: @config.producer_class,
                                         last_sent: Time.new(0))
      end

      # Stop the poll.
      def stop
        Deimos.config.logger.info('Received signal to stop')
        @signal_to_stop = true
      end

      # Indicate whether this current loop should process updates. Most loops
      # will busy-wait (sleeping 1/2 second) until it's ready.
      # @return [Boolean]
      def should_run?
        Time.zone.now - @info.last_sent >= @config.run_every
      end

      # Send messages for updated data.
      def process_updates
        return unless should_run?

        time_from = @info.last_sent.in_time_zone
        time_to = Time.zone.now - @config.delay_time
        Deimos.config.logger.info("Polling #{@producer.topic} from #{time_from} to #{time_to}")
        message_count = 0
        batch_count = 1

        # poll_query gets all the relevant data from the database, as defined
        # by the producer itself.
        @producer.poll_query(time_from,
                             time_to,
                             @config.timestamp_column,
                             @config.full_table).
          find_in_batches(batch_size: BATCH_SIZE) do |batch|
            Deimos.config.logger.debug("Polling #{@producer.topic}, batch #{batch_count} (starting #{batch.first.id})")
            @producer.send_events(batch)
            message_count += batch.size
            batch_count += 1
          end
        @info.update_attribute(:last_sent, time_to)
        Deimos.config.logger.info("Poll #{@producer.topic} complete at #{time_to} (#{message_count} messages, #{batch_count} batches}")
      end
    end
  end
end
