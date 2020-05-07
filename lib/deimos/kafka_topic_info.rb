# frozen_string_literal: true

module Deimos
  # Record that keeps track of which topics are being worked on by DbProducers.
  class KafkaTopicInfo < ActiveRecord::Base
    self.table_name = 'kafka_topic_info'

    class << self
      # Lock a topic for the given ID. Returns whether the lock was successful.
      # @param topic [String]
      # @param lock_id [String]
      # @return [Boolean]
      def lock(topic, lock_id)
        # Try to create it - it's fine if it already exists
        begin
          self.create(topic: topic)
        rescue ActiveRecord::RecordNotUnique
          # continue on
        end

        # Lock the record
        qtopic = self.connection.quote(topic)
        qlock_id = self.connection.quote(lock_id)
        qtable = self.connection.quote_table_name('kafka_topic_info')
        qnow = self.connection.quote(Time.zone.now.to_s(:db))
        qfalse = self.connection.quoted_false
        qtime = self.connection.quote(1.minute.ago.to_s(:db))

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
      def clear_lock(topic, lock_id)
        self.where(topic: topic, locked_by: lock_id).
          update_all(locked_by: nil, locked_at: nil, error: false, retries: 0)
      end

      # The producer calls this if it gets an error sending messages. This
      # essentially locks down this topic for 1 minute (for all producers)
      # and allows the caller to continue to the next topic.
      # @param topic [String]
      # @param lock_id [String]
      def register_error(topic, lock_id)
        record = self.where(topic: topic, locked_by: lock_id).last
        attr_hash = { locked_by: nil,
                      locked_at: Time.zone.now,
                      error: true,
                      retries: record.retries + 1 }
        if ActiveRecord::VERSION::MAJOR >= 4
          record.update!(attr_hash)
        else
          record.update_attributes!(attr_hash)
        end
      end

      # Update the locked_at timestamp to indicate that the producer is still
      # working on those messages and to continue.
      # @param topic [String]
      # @param lock_id [String]
      def heartbeat(topic, lock_id)
        self.where(topic: topic, locked_by: lock_id).
          update_all(locked_at: Time.zone.now)
      end
    end
  end
end
