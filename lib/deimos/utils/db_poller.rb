# frozen_string_literal: true

require 'deimos/poll_info'
require 'sigurd'

module Deimos
  module Utils
    # Class which continually polls the database and sends Kafka messages.
    class DbPoller
      # @return [Integer]
      BATCH_SIZE = 1000

      # Needed for Executor so it can identify the worker
      # @return [Integer]
      attr_reader :id

      # @return [Hash]
      attr_reader :config

      # Begin the DB Poller process.
      # @return [void]
      def self.start!
        if Deimos.config.db_poller_objects.empty?
          raise('No pollers configured!')
        end

        pollers = Deimos.config.db_poller_objects.map do |poller_config|
          self.new(poller_config)
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
      # @return [void]
      def retrieve_poll_info
        ActiveRecord::Base.connection.reconnect! unless ActiveRecord::Base.connection.open_transactions.positive?
        new_time = @config.start_from_beginning ? Time.new(0) : Time.zone.now
        @info = Deimos::PollInfo.find_by_producer(@config.producer_class) ||
                Deimos::PollInfo.create!(producer: @config.producer_class,
                                         last_sent: new_time,
                                         last_sent_id: 0)
      end

      # Stop the poll.
      # @return [void]
      def stop
        Deimos.config.logger.info('Received signal to stop')
        @signal_to_stop = true
      end

      # Indicate whether this current loop should process updates. Most loops
      # will busy-wait (sleeping 0.1 seconds) until it's ready.
      # @return [Boolean]
      def should_run?
        Time.zone.now - @info.last_sent - @config.delay_time >= @config.run_every
      end

      # @param record [ActiveRecord::Base]
      # @return [ActiveSupport::TimeWithZone]
      def last_updated(record)
        record.public_send(@config.timestamp_column)
      end

      # Send messages for updated data.
      # @return [void]
      def process_updates
        return unless should_run?

        time_from = @config.full_table ? Time.new(0) : @info.last_sent.in_time_zone
        time_to = Time.zone.now - @config.delay_time
        Deimos.config.logger.info("Polling #{@producer.topic} from #{time_from} to #{time_to}")
        message_count = 0
        batch_count = 0
        error_count = 0

        # poll_query gets all the relevant data from the database, as defined
        # by the producer itself.
        loop do
          Deimos.config.logger.debug("Polling #{@producer.topic}, batch #{batch_count + 1}")
          batch = fetch_results(time_from, time_to).to_a
          break if batch.empty?

          if process_batch_with_span(batch)
            batch_count += 1
          else
            error_count += 1
          end
          message_count += batch.size
          time_from = last_updated(batch.last)
        end
        Deimos.config.logger.info("Poll #{@producer.topic} complete at #{time_to} (#{message_count} messages, #{batch_count} successful batches, #{error_count} batches errored}")
      end

      # @param time_from [ActiveSupport::TimeWithZone]
      # @param time_to [ActiveSupport::TimeWithZone]
      # @return [ActiveRecord::Relation]
      def fetch_results(time_from, time_to)
        id = @producer.config[:record_class].primary_key
        quoted_timestamp = ActiveRecord::Base.connection.quote_column_name(@config.timestamp_column)
        quoted_id = ActiveRecord::Base.connection.quote_column_name(id)
        @producer.poll_query(time_from: time_from,
                             time_to: time_to,
                             column_name: @config.timestamp_column,
                             min_id: @info.last_sent_id).
          limit(BATCH_SIZE).
          order("#{quoted_timestamp}, #{quoted_id}")
      end

      # @param batch [Array<ActiveRecord::Base>]
      # @return [void]
      def process_batch_with_span(batch)
        retries = 0
        begin
          span = Deimos.config.tracer&.start(
            'deimos-db-poller',
            resource: @producer.class.name.gsub('::', '-')
          )
          process_batch(batch)
          Deimos.config.tracer&.finish(span)
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
            self.touch_info(batch)
            return false
          end
        end
        true
      end

      # @param batch [Array<ActiveRecord::Base>]
      # @return [void]
      def touch_info(batch)
        record = batch.last
        id_method = record.class.primary_key
        last_id = record.public_send(id_method)
        last_updated_at = last_updated(record)
        @info.attributes = { last_sent: last_updated_at, last_sent_id: last_id }
        @info.save!
      end

      # @param batch [Array<ActiveRecord::Base>]
      # @return [void]
      def process_batch(batch)
        @producer.send_events(batch)
        self.touch_info(batch)
      end
    end
  end
end
