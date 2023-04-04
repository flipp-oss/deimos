# frozen_string_literal: true

require 'deimos/utils/db_poller/base'

module Deimos
  module Utils
    module DbPoller
      # Poller that uses state columns to determine the records to publish.
      class StateBased < Base
        # Send messages for updated data.
        # @return [void]
        def process_updates
          Deimos.config.logger.info("Polling #{@producers.map(&:topic)}")
          status = PollStatus.new(0, 0, 0)

          # poll_query gets all the relevant data from the database, as defined
          # by the producer itself.
          loop do
            Deimos.config.logger.debug("Polling #{@producers.map(&:topic)}, batch #{status.current_batch}")
            batch = fetch_results.to_a
            if batch.empty?
              @info.touch(:last_sent)
              break
            end

            success = process_batch_with_span(batch, status)
            finalize_batch(batch, success)
          end
          Deimos.config.logger.info("Poll #{@producers.map(&:topic)} complete (#{status.report}")
        end

        # @return [ActiveRecord::Relation]
        def fetch_results
          if @poller_class.nil?
            @producer.poll_query.limit(BATCH_SIZE).order(@config.timestamp_column)
          else
            @poller_class.poll_query.limit(BATCH_SIZE).order(@config.timestamp_column)
          end
        end

        # @param batch [Array<ActiveRecord::Base>]
        # @param success [Boolean]
        # @return [void]
        def finalize_batch(batch, success)
          @info.touch(:last_sent)

          state = success ? @config.published_state : @config.failed_state
          klass = batch.first.class
          id_col = klass.primary_key.to_sym
          timestamp_col = @config.timestamp_column

          attrs = { timestamp_col => Time.zone.now }
          attrs[@config.state_column] = state if state
          if @config.publish_timestamp_column
            attrs[@config.publish_timestamp_column] = Time.zone.now
          end

          klass.where(id_col => batch.map(&id_col)).update_all(attrs)
        end

      end
    end
  end
end
