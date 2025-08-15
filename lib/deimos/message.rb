# frozen_string_literal: true

module Deimos
  # Basically a struct to hold the message as it's processed.
  class Message
    # @return [Hash]
    attr_accessor :payload
    # @return [Hash, String, Integer]
    attr_accessor :key
    # @return [Hash]
    attr_accessor :headers
    # @return [Integer]
    attr_accessor :partition_key
    # @return [String]
    attr_accessor  :encoded_key
    # @return [String]
    attr_accessor  :encoded_payload
    # @return [String]
    attr_accessor  :topic

    # @param payload [Hash]
    # @param topic [String]
    # @param key [String, Integer, Hash]
    # @param partition_key [Integer]
    def initialize(payload, topic: nil, key: nil, headers: nil, partition_key: nil)
      @payload = payload
      @payload = @payload.with_indifferent_access if @payload.is_a?(Hash)
      @topic = topic
      @key = key
      @headers = headers&.with_indifferent_access
      @partition_key = partition_key
    end

    # Add message_id and timestamp default values if they are in the
    # schema and don't already have values.
    # @param fields [Array<String>] existing name fields in the schema.
    # @return [void]
    def add_fields(fields)
      return if @payload.to_h.except(:payload_key, :partition_key).blank?

      if fields.include?('message_id')
        @payload['message_id'] ||= SecureRandom.uuid
      end
      if fields.include?('timestamp')
        @payload['timestamp'] ||= Time.now.in_time_zone.to_s
      end
    end

    # @param encoder [Deimos::SchemaBackends::Base]
    # @return [void]
    def coerce_fields(encoder)
      return if payload.nil?

      @payload = encoder.coerce(@payload)
    end

    # @return [Hash]
    def encoded_hash
      {
        topic: @topic,
        key: @encoded_key,
        headers: @headers,
        partition_key: @partition_key || @encoded_key,
        payload: @encoded_payload
      }.delete_if { |k, v| k == :headers && v.nil? }
    end

    # @return [Hash]
    def to_h
      {
        topic: @topic,
        key: @key,
        headers: @headers,
        partition_key: @partition_key || @key,
        payload: @payload,
        metadata: {
          decoded_payload: @payload,
        }
      }.delete_if { |k, v| k == :headers && v.nil? }
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
