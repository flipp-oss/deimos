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
      @producer_name = producer.name
      @topic = topic
      @key = key
      @partition_key = partition_key
    end

    # Add message_id and timestamp default values if they are in the
    # schema and don't already have values.
    # @param schema [Avro::Schema]
    def add_fields(schema)
      return if @payload.except(:payload_key, :partition_key).blank?

      if schema.fields.any? { |f| f.name == 'message_id' }
        @payload['message_id'] ||= SecureRandom.uuid
      end
      if schema.fields.any? { |f| f.name == 'timestamp' }
        @payload['timestamp'] ||= Time.now.in_time_zone.to_s
      end
    end

    # @param schema [Avro::Schema]
    def coerce_fields(schema)
      return if payload.nil?

      @payload = SchemaCoercer.new(schema).coerce(@payload)
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
  end
end
