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
      write_attribute(:message, mess ? mess.to_s : nil)
    end

    # @return [Deimos::Consumer]
    def decoder
      producer = Deimos::Producer.descendants.find { |c| c.topic == self.topic }
      return nil unless producer

      consumer = Class.new(Deimos::Consumer)
      consumer.config.merge!(producer.config)
      consumer
    end

    # Decode the message. This assumes for now that we have access to a producer
    # in the codebase which can decode it.
    # @param decoder [Deimos::Consumer]
    # @return [Hash]
    def decoded_message(decoder=self.decoder)
      return { key: self.key, message: self.message } unless decoder

      {
        key: self.key.present? ? decoder.new.decode_key(self.key) : nil,
        payload: decoder.decoder.decode(self.message)
      }
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
