# frozen_string_literal: true

module Deimos
  # Record that keeps track of which topics are being worked on by OutboxProducers.
  class KafkaTopicInfo < ActiveRecord::Base
    self.table_name = 'kafka_topic_info'

    class << self

      def quote_time(time)
        time.respond_to?(:to_fs) ? time.to_fs(:db) : time.to_s(:db)
      end

      # Lock a topic for the given ID. Returns whether the lock was successful.
      # @param topic [String]
      # @param lock_id [String]
      # @return [Boolean]
      def lock(topic, lock_id)
        # Try to create it - it's fine if it already exists
        begin
          self.create(topic: topic, last_processed_at: Time.zone.now)
        rescue ActiveRecord::RecordNotUnique
          # continue on
        end

        # Lock the record
        qtopic = self.connection.quote(topic)
        qlock_id = self.connection.quote(lock_id)
        qtable = self.connection.quote_table_name('kafka_topic_info')
        qnow = self.connection.quote(quote_time(Time.zone.now))
        qfalse = self.connection.quoted_false
        qtime = self.connection.quote(quote_time(1.minute.ago))

        # If a record is marked as error and less than 1 minute old,
        # we don't want to pick it up even if not currently locked because
        # we worry we'll run into the same problem again.
        # Once it's more than 1 minute old, we figure it's OK to try again
        # so we can pick up any topic that's that old, even if it was
        # locked by someone, because it's the job of the producer to keep
        # updating the locked_at timestamp as they work on messages in that
        # topic. If the locked_at timestamp is that old, chances are that
        # the producer crashed.
        sql = <<~SQL
          UPDATE #{qtable}
          SET locked_by=#{qlock_id}, locked_at=#{qnow}, error=#{qfalse}
          WHERE topic=#{qtopic} AND
           ((locked_by IS NULL AND error=#{qfalse}) OR locked_at < #{qtime})
        SQL
        self.connection.update(sql)
        self.where(locked_by: lock_id, topic: topic).any?
      end

      # This is called once a producer is finished working on a topic, i.e.
      # there are no more messages to fetch. It unlocks the topic and
      # moves on to the next one.
      # @param topic [String]
      # @param lock_id [String]
      # @return [void]
      def clear_lock(topic, lock_id)
        self.where(topic: topic, locked_by: lock_id).
          update_all(locked_by: nil,
                     locked_at: nil,
                     error: false,
                     retries: 0,
                     last_processed_at: Time.zone.now)
      end

      # Update all topics that aren't currently locked and have no messages
      # waiting. It's OK if some messages get inserted in the middle of this
      # because the point is that at least within a few milliseconds of each
      # other, it wasn't locked and had no messages, meaning the topic
      # was in a good state.
      # @param except_topics [Array<String>] the list of topics we've just
      # realized had messages in them, meaning all other topics were empty.
      # @return [void]
      def ping_empty_topics(except_topics)
        records = KafkaTopicInfo.where(locked_by: nil).
          where('topic not in(?)', except_topics)
        records.each do |info|
          info.update_attribute(:last_processed_at, Time.zone.now)
        end
      end

      # The producer calls this if it gets an error sending messages. This
      # essentially locks down this topic for 1 minute (for all producers)
      # and allows the caller to continue to the next topic.
      # @param topic [String]
      # @param lock_id [String]
      # @return [void]
      def register_error(topic, lock_id)
        record = self.where(topic: topic, locked_by: lock_id).last
        attr_hash = { locked_by: nil,
                      locked_at: Time.zone.now,
                      error: true,
                      retries: record.retries + 1 }
        record.attributes = attr_hash
        record.save!
      end

      # Update the locked_at timestamp to indicate that the producer is still
      # working on those messages and to continue.
      # @param topic [String]
      # @param lock_id [String]
      # @return [void]
      def heartbeat(topic, lock_id)
        self.where(topic: topic, locked_by: lock_id).
          update_all(locked_at: Time.zone.now)
      end
    end
  end
end
