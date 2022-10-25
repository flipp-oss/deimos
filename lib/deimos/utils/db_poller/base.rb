# frozen_string_literal: true

require 'deimos/poll_info'
require 'sigurd'

module Deimos
  module Utils
    # Class which continually polls the database and sends Kafka messages.
    module DbPoller

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

      class Base

        # @return [Integer]
        BATCH_SIZE = 1000

        # Needed for Executor so it can identify the worker
        # @return [Integer]
        attr_reader :id

        # @return [Hash]
        attr_reader :config

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

        # @param config [FigTree::ConfigStruct]
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
        # @return [void]
        def start
          # Don't send asynchronously
          if Deimos.config.producers.backend == :kafka_async
            Deimos.config.producers.backend = :kafka
          end
          Deimos.config.logger.info('Starting...')
          @signal_to_stop = false
          ActiveRecord::Base.connection.reconnect! unless ActiveRecord::Base.connection.open_transactions.positive?

          retrieve_poll_info
          loop do
            if @signal_to_stop
              Deimos.config.logger.info('Shutting down')
              break
            end
            process_updates if should_run?
            sleep 0.1
          end
        end

        # @return [void]
        # Grab the PollInfo or create if it doesn't exist.
        # @return [void]
        def retrieve_poll_info
          @info = Deimos::PollInfo.find_by_producer(@config.producer_class) || create_poll_info
        end

        # @return [Deimos::PollInfo]
        def create_poll_info
          Deimos::PollInfo.create!(producer: @config.producer_class, last_sent: Time.new(0))
        end

        # Indicate whether this current loop should process updates. Most loops
        # will busy-wait (sleeping 0.1 seconds) until it's ready.
        # @return [Boolean]
        def should_run?
          Time.zone.now - @info.last_sent - @config.delay_time >= @config.run_every
        end

        # Stop the poll.
        # @return [void]
        def stop
          Deimos.config.logger.info('Received signal to stop')
          @signal_to_stop = true
        end

        # Send messages for updated data.
        # @return [void]
        def process_updates
          raise Deimos::MissingImplementationError
        end

        # @param batch [Array<ActiveRecord::Base>]
        # @param status [PollStatus]
        # @return [Boolean]
        def process_batch_with_span(batch, status)
          retries = 0
          begin
            span = Deimos.config.tracer&.start(
              'deimos-db-poller',
              resource: @producer.class.name.gsub('::', '-')
            )
            process_batch(batch)
            Deimos.config.tracer&.finish(span)
            status.batches_processed += 1
          rescue Kafka::Error => e # keep trying till it fixes itself
            Deimos.config.logger.error("Error publishing through DB Poller: #{e.message}")
            sleep(0.5)
            retry
          rescue StandardError => e
            Deimos.config.logger.error("Error publishing through DB poller: #{e.message}}")
            if retries < @config.retries
              retries += 1
              sleep(0.5)
              retry
            else
              Deimos.config.logger.error('Retries exceeded, moving on to next batch')
              Deimos.config.tracer&.set_error(span, e)
              status.batches_errored += 1
              return false
            end
          ensure
            status.messages_processed += batch.size
          end
          true
        end

        # @param batch [Array<ActiveRecord::Base>]
        # @return [void]
        def process_batch(batch)
          @producer.send_events(batch)
        end
      end
    end
  end
end

require 'deimos/utils/db_poller/time_based'
require 'deimos/utils/db_poller/state_based'
