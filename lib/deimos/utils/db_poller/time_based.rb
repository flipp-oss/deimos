# frozen_string_literal: true

require 'deimos/utils/db_poller/base'

module Deimos
  module Utils
    module DbPoller
      # Poller that uses ID and updated_at to determine the records to publish.
      class TimeBased < Base

        # :nodoc:
        def create_poll_info
          new_time = @config.start_from_beginning ? Time.new(0) : Time.zone.now
          Deimos::PollInfo.create!(producer: @resource_class.to_s,
                                   last_sent: new_time,
                                   last_sent_id: 0)
        end

        # @param batch [Array<ActiveRecord::Base>]
        # @param status [Deimos::Utils::DbPoller::PollStatus]
        # @return [void]
        def process_and_touch_info(batch, status)
          process_batch_with_span(batch, status)
          self.touch_info(batch)
        end

        # Send messages for updated data.
        # @return [void]
        def process_updates
          time_from = @config.full_table ? Time.new(0) : @info.last_sent.in_time_zone
          time_to = Time.zone.now - @config.delay_time
          Deimos.config.logger.info("Polling #{log_identifier} from #{time_from} to #{time_to}")
          status = PollStatus.new(0, 0, 0)
          first_batch = true

          # poll_query gets all the relevant data from the database, as defined
          # by the producer itself.
          loop do
            Deimos.config.logger.debug("Polling #{log_identifier}, batch #{status.current_batch}")
            batch = fetch_results(time_from, time_to).to_a
            break if batch.empty?

            first_batch = false
            process_and_touch_info(batch, status)
            time_from = last_updated(batch.last)
          end

          # If there were no results at all, we update last_sent so that we still get a wait
          # before the next poll.
          @info.touch(:last_sent) if first_batch
          Deimos.config.logger.info("Poll #{log_identifier} complete at #{time_to} (#{status.report})")
        end

        # @param time_from [ActiveSupport::TimeWithZone]
        # @param time_to [ActiveSupport::TimeWithZone]
        # @return [ActiveRecord::Relation]
        def fetch_results(time_from, time_to)
          id = self.producer_classes.first.config[:record_class].primary_key
          quoted_timestamp = ActiveRecord::Base.connection.quote_column_name(@config.timestamp_column)
          quoted_id = ActiveRecord::Base.connection.quote_column_name(id)
          @resource_class.poll_query(time_from: time_from,
                                     time_to: time_to,
                                     column_name: @config.timestamp_column,
                                     min_id: @info.last_sent_id).
            limit(BATCH_SIZE).
            order("#{quoted_timestamp}, #{quoted_id}")
        end

        # @param record [ActiveRecord::Base]
        # @return [ActiveSupport::TimeWithZone]
        def last_updated(record)
          record.public_send(@config.timestamp_column)
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

      end
    end
  end
end
