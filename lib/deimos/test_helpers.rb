# frozen_string_literal: true

require 'active_support/concern'
require 'active_support/core_ext'
require 'deimos/tracing/mock'
require 'deimos/metrics/mock'

module Deimos
  # Include this module in your RSpec spec_helper
  # to stub out external dependencies
  # and add methods to use to test encoding/decoding.
  module TestHelpers
    extend ActiveSupport::Concern

    class << self
      # for backwards compatibility
      # @return [Array<Hash>]
      def sent_messages
        produced_messages
      end

      # Set the config to the right settings for a unit test
      # @return [void]
      def unit_test!
        Deimos.configure do |deimos_config|
          deimos_config.logger = Logger.new(STDOUT)
          deimos_config.consumers.reraise_errors = true
          deimos_config.schema.backend = Deimos.schema_backend_class.mock_backend
          deimos_config.producers.backend = :test
          deimos_config.tracer = Deimos::Tracing::Mock.new
        end
      end
    end

    # get the difference of 2 hashes.
    # @param hash1 [Hash, nil]
    # @param hash2 [Hash, nil]
    # @!visibility private
    def _hash_diff(hash1, hash2)
      h1 = normalize_message(hash1)
      h2 = normalize_message(hash2)
      if h1.nil? || !h1.is_a?(Hash)
        h2
      elsif h2.nil? || !h2.is_a?(Hash)
        h1
      else
        h1.dup.
          delete_if { |k, v| h2[k] == v }.
          merge!(h2.dup.delete_if { |k, _v| h1.key?(k) })
      end
    end

    def normalize_message(m)
      return nil if m.nil?

      if m.respond_to?(:to_h)
        m = m.to_h
      end
      if m.respond_to?(:with_indifferent_access)
        m = m.with_indifferent_access
      end
      m
    end

    # @!visibility private
    def _frk_failure_message(topic, message, key=nil, partition_key=nil, was_negated=false)
      messages = produced_messages.select { |m| m.metadata.topic == topic }
      message_string = ''
      diff = nil
      min_hash_diff = nil
      message = normalize_message(message)
      if messages.any?
        message_string = messages.map { |m| normalize_message(m.payload).inspect}.join("\n")
        min_hash_diff = messages.min_by { |m| _hash_diff(m, message)&.keys&.size }
        diff = RSpec::Expectations.differ.diff_as_object(message, min_hash_diff.payload)
      end
      str = "Expected #{topic} #{'not ' if was_negated}to have sent #{message&.to_h}"
      str += " with key #{key}" if key
      str += " with partition key #{partition_key}" if partition_key
      str += "\nClosest message received: #{min_hash_diff}" if min_hash_diff
      str += "\nDiff: #{diff}" if diff
      str + "\nAll Messages received:\n#{message_string}"
    end

    RSpec::Matchers.define :have_sent do |msg, key=nil, partition_key=nil, headers=nil|
      message = normalize_message(msg)
      match do |topic|
        produced_messages.any? do |m|
          message_hash = normalize_message(message&.payload)
          hash_matcher = RSpec::Matchers::BuiltIn::Match.new(message_hash)
          hash_matcher.send(:match,
                            message_hash,
                            m.payload&.to_h&.with_indifferent_access) &&
            topic == m.metadata.topic &&
            (key.present? ? key == m.metadata.key : true) &&
            (partition_key.present? ? partition_key == m.partition_key : true) &&
            if headers.present?
              hash_matcher.send(:match,
                                headers.with_indifferent_access,
                                m.metadata.headers&.with_indifferent_access)
            else
              true
            end
        end
      end

      failure_message do |topic|
        _frk_failure_message(topic, message, key, partition_key)
      end
      failure_message_when_negated do |topic|
        _frk_failure_message(topic, message, key, partition_key, true)
      end
    end

    # Clear all sent messages - e.g. if we want to check that
    # particular messages were sent or not sent after a point in time.
    # @return [void]
    def clear_kafka_messages!
      produced_messages.clear
    end

    # Test that a given handler will consume a given payload correctly, i.e.
    # that the schema is correct. If
    # a block is given, that block will be executed when `consume` is called.
    # Otherwise it will just confirm that `consume` is called at all.
    # @param handler_class_or_topic [Class, String] Class which inherits from
    # Deimos::Consumer or the topic as a string
    # @param payload [Hash] the payload to consume
    # @param key [Object] the key to use.
    # @param partition_key [Object] the partition key to use.
    # @return [void]
    def test_consume_message(handler_class_or_topic,
                             payload,
                             key: nil,
                             partition_key: nil,
                             &block)
      test_consume_batch(handler_class_or_topic, [payload], keys: [key], partition_keys: [partition_key], &block)
    end

    # Test that a given handler will consume a given batch payload correctly,
    # i.e. that the schema is correct. If
    # a block is given, that block will be executed when `consume` is called.
    # Otherwise it will just confirm that `consume` is called at all.
    # @param handler_class_or_topic [Class, String] Class which inherits from
    # Deimos::Consumer or the topic as a string
    # @param payloads [Array<Hash>] the payload to consume
    # @param keys [Array<Hash,String>]
    # @param partition_keys [Array<Integer>]
    # @return [void]
    def test_consume_batch(handler_class_or_topic,
                           payloads,
                           keys: [],
                           partition_keys: [],
                           &block)
      handler_class = nil
      topic_name = nil
      if handler_class_or_topic.is_a?(String)
        topic_name = handler_class_or_topic
        handler_class = Deimos.consumer_config(topic_name, :class_name).constantize
      else
        handler_class = handler_class_or_topic
        topic_name = Deimos.topic_for_consumer(handler_class_or_topic)
      end
      if block_given?
        allow(handler_class).to receive(:consume, &block)
      end
      payloads.each_with_index do |payload, i|
        karafka.produce(payload, key: keys[i], partition_key: partition_keys[i], topic: topic_name)
      end
      consumer.consume
    end

  end
end
