# frozen_string_literal: true

module Deimos
  # Store Kafka messages into the database.
  class KafkaMessage < ActiveRecord::Base
    self.table_name = 'kafka_messages'

    validates_presence_of :topic

    # Ensure it gets turned into a string, e.g. for testing purposes. It
    # should already be a string.
    # @param mess [Object]
    def message=(mess)
      write_attribute(:message, mess.to_s)
    end

    # @return [Hash]
    def phobos_message
      {
        payload: self.message,
        partition_key: self.partition_key,
        key: self.key,
        topic: self.topic
      }
    end

  end
end
