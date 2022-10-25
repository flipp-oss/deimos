require 'deimos/utils/db_poller/base'

module Deimos
  module Utils
    module DbPoller
      class StateBased < Base
        # Send messages for updated data.
        # @return [void]
        def process_updates
          Deimos.config.logger.info("Polling #{@producer.topic}")
          status = PollStatus.new(0, 0, 0)

          # poll_query gets all the relevant data from the database, as defined
          # by the producer itself.
          loop do
            Deimos.config.logger.debug("Polling #{@producer.topic}, batch #{status.current_batch}")
            batch = fetch_results.to_a
            break if batch.empty?

            success = process_batch_with_span(batch, status)
            finalize_batch(batch, success)
          end
          Deimos.config.logger.info("Poll #{@producer.topic} complete (#{status.report}")
        end

        # @return [ActiveRecord::Relation]
        def fetch_results
          @producer.poll_query.limit(BATCH_SIZE).order(@config.timestamp_column)
        end

        # @param batch [Array<ActiveRecord::Base>]
        # @param success [Boolean]
        # @return [void]
        def finalize_batch(batch, success)
          @info.touch

          state = success ? @config.published_state : @config.failed_state
          klass = batch.first.class
          id_col = record.class.primary_key
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
