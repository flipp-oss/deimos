# frozen_string_literal: true

module Deimos
  # Basically a struct to hold the message as it's processed.
  class Message
    attr_accessor :payload, :key, :partition_key, :encoded_key,
                  :encoded_payload, :topic, :producer_name

    # @param payload [Hash]
    # @param producer [Class]
    def initialize(payload, producer, topic: nil, key: nil, partition_key: nil)
      @payload = payload&.with_indifferent_access
      @producer_name = producer&.name
      @topic = topic
      @key = key
      @partition_key = partition_key
    end

    # Add message_id and timestamp default values if they are in the
    # schema and don't already have values.
    # @param fields [Array<String>] existing name fields in the schema.
    def add_fields(fields)
      return if @payload.except(:payload_key, :partition_key).blank?

      if fields.include?('message_id')
        @payload['message_id'] ||= SecureRandom.uuid
      end
      if fields.include?('timestamp')
        @payload['timestamp'] ||= Time.now.in_time_zone.to_s
      end
    end

    # @param encoder [Deimos::SchemaBackends::Base]
    def coerce_fields(encoder)
      return if payload.nil?

      @payload = encoder.coerce(@payload)
    end

    # @return [Hash]
    def encoded_hash
      {
        topic: @topic,
        key: @encoded_key,
        partition_key: @partition_key || @encoded_key,
        payload: @encoded_payload,
        metadata: {
          decoded_payload: @payload,
          producer_name: @producer_name
        }
      }
    end

    # @return [Hash]
    def to_h
      {
        topic: @topic,
        key: @key,
        partition_key: @partition_key || @key,
        payload: @payload,
        metadata: {
          decoded_payload: @payload,
          producer_name: @producer_name
        }
      }
    end

    # @param other [Message]
    # @return [Boolean]
    def ==(other)
      self.to_h == other.to_h
    end

    # @return [Boolean] True if this message is a tombstone
    def tombstone?
      payload.nil?
    end
  end
end
