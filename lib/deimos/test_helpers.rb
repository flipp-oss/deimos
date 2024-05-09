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
        karafka.produced_messages
      end

      # Set the config to the right settings for a unit test
      # @return [void]
      def unit_test!
        Deimos.configure do |deimos_config|
          deimos_config.logger = Logger.new(STDOUT)
          deimos_config.consumers.reraise_errors = true
          deimos_config.schema.backend = :avro_local
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

    def self.normalize_message(m)
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
      messages = karafka.produced_messages.select { |m| m.metadata.topic == topic }
      message_string = ''
      diff = nil
      min_hash_diff = nil
      message = Deimos::TestHelpers.normalize_message(message)
      if messages.any?
        message_string = messages.map { |m| Deimos::TestHelpers.normalize_message(m.payload).inspect}.join("\n")
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
      message = Deimos::TestHelpers.normalize_message(msg)
      match do |topic|
        message_hash = Deimos::TestHelpers.normalize_message(message)
        hash_matcher = RSpec::Matchers::BuiltIn::Match.new(message_hash)
        karafka.produced_messages.any? do |m|
          Deimos.decode_message(m)
          payload = Deimos::TestHelpers.normalize_message(m[:payload]&.to_h)
          hash_matcher.send(:match, message_hash, payload) &&
            topic == m[:topic] &&
            (key.present? ? key == m[:key] : true) &&
            (partition_key.present? ? partition_key == m[:partition_key] : true) &&
            if headers.present?
              hash_matcher.send(:match,
                                headers.with_indifferent_access,
                                m[:headers]&.with_indifferent_access)
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
      karafka.produced_messages.clear
    end

    # Test that a given handler will consume a given payload correctly, i.e.
    # that the schema is correct. If
    # a block is given, that block will be executed when `consume` is called.
    # Otherwise it will just confirm that `consume` is called at all.
    # @param handler_class_or_topic [Class, String] Class which inherits from
    # Deimos::Consumer or the topic as a string
    # @param payload [Hash] the payload to consume
    # @param key [Object] the key to use.
    # @param call_original [Symbol] legacy parameter.
    # @param partition_key [Object] the partition key to use.
    # @return [void]
    def test_consume_message(handler_class_or_topic,
                             payload,
                             key: nil,
                             call_original: :not_given,
                             partition_key: nil)
      if call_original != :not_given
        puts "test_consume_message(call_original: true) is deprecated and will be removed in the future. You can remove the call_original parameter."
      end
      test_consume_batch(handler_class_or_topic, [payload], keys: [key], partition_keys: [partition_key])
    end

    # Test that a given handler will consume a given batch payload correctly,
    # i.e. that the schema is correct. If
    # a block is given, that block will be executed when `consume` is called.
    # Otherwise it will just confirm that `consume` is called at all.
    # @param handler_class_or_topic [Class, String] Class which inherits from
    # Deimos::Consumer or the topic as a string
    # @param payloads [Array<Hash>] the payload to consume
    # @param call_original [Symbol] legacy parameter.
    # @param keys [Array<Object>]
    # @param partition_keys [Array<Object>]
    # @return [void]
    def test_consume_batch(handler_class_or_topic,
                           payloads,
                           keys: [],
                           call_original: :not_given,
                           partition_keys: [])
      if call_original != :not_given
        puts "test_consume_batch(call_original: true) is deprecated and will be removed in the future. You can remove the call_original parameter."
      end
      consumer = nil
      if handler_class_or_topic.is_a?(String)
        topic_name = handler_class_or_topic
        consumer = karafka.consumer_for(topic_name)
      else
        topic_name = Deimos.topic_for_consumer(handler_class_or_topic)
        consumer = karafka.consumer_for(topic_name)
      end
      karafka.set_consumer(consumer)

       payloads.each_with_index do |payload, i|
         karafka.produce(payload, {key: keys[i], partition_key: partition_keys[i], topic: consumer.topic.name})
       end
       consumer.consume
      end
  end
end
