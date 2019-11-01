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

    # Decoded payload for this message.
    # @return [Hash]
    def decoded_message
      self.class.decoded([self]).first
    end

    # Get a decoder to decode a set of messages on the given topic.
    # @param topic [String]
    # @return [Deimos::Consumer]
    def self.decoder(topic)
      producer = Deimos::Producer.descendants.find { |c| c.topic == topic }
      return nil unless producer

      consumer = Class.new(Deimos::Consumer)
      consumer.config.merge!(producer.config)
      consumer
    end

    # Decoded payloads for a list of messages.
    # @param messages [Array<Deimos::KafkaMessage>]
    # @return [Array<Hash>]
    def self.decoded(messages=[])
      return [] if messages.empty?

      decoder = self.decoder(messages.first.topic)&.new
      messages.map do |m|
        {
          key: m.key.present? ? decoder&.decode_key(m.key) || m.key : nil,
          payload: decoder&.decoder&.decode(self.message) || self.message
        }
      end
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
