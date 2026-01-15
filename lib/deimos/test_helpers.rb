# frozen_string_literal: true

require 'active_support/concern'
require 'active_support/core_ext'
require 'deimos/tracing/mock'
require 'deimos/metrics/mock'
require 'karafka/testing/rspec/helpers'

module Deimos
  # Include this module in your RSpec spec_helper
  # to stub out external dependencies
  # and add methods to use to test encoding/decoding.
  module TestHelpers
    extend ActiveSupport::Concern

    def self.included(base)
      super
      base.include Karafka::Testing::RSpec::Helpers

      # Ensure that we only use Karafka.producer, not the producers we set up for multi-broker
      # configs. Only Karafka.producer works with Karafka test helpers.
      RSpec.configure do |config|
        config.before(:each) do
          allow(Deimos).to receive(:producer_for).and_return(Karafka.producer)
        end
      end
    end

    # @return [Array<Hash>]
    def sent_messages
      self.class.sent_messages
    end

    class << self
      # @return [Array<Hash>]
      def sent_messages
        Karafka.producer.client.messages.map do |m|
          produced_message = m.except(:label).deep_dup
          Deimos.decode_message(produced_message)
          produced_message[:payload] = Deimos::TestHelpers.normalize_message(produced_message[:payload])
          produced_message[:key] = Deimos::TestHelpers.normalize_message(produced_message[:key])
          produced_message
        end
      end

      # Set the config to the right settings for a unit test
      # @return [void]
      def unit_test!
        Deimos.config.schema.backend = :avro_validation
        warn("unit_test! is deprecated and can be replaced by setting Deimos's schema backend " \
             'to `:avro_validation`. All other test behavior is provided by Karafka.')
      end

      def with_mock_backends
        Deimos.mock_backends = true
        yield
        Deimos.mock_backends = false
      end

    end

    # get the difference of 2 hashes.
    # @param hash1 [Hash, nil]
    # @param hash2 [Hash, nil]
    # @!visibility private
    def _hash_diff(hash1, hash2)
      h1 = Deimos::TestHelpers.normalize_message(hash1)
      h2 = Deimos::TestHelpers.normalize_message(hash2)
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

    def self.normalize_message(message)
      return nil if message.nil?

      if message.respond_to?(:to_h)
        message = message.to_h
      end
      if message.respond_to?(:with_indifferent_access)
        message = message.with_indifferent_access
      end
      message
    end

    # @!visibility private
    def _frk_failure_message(topic, message, key=nil, partition_key=nil, was_negated=false)
      messages = Deimos::TestHelpers.sent_messages.select { |m| m[:topic] == topic }
      message_string = ''
      diff = nil
      min_hash_diff = nil
      message = Deimos::TestHelpers.normalize_message(message)
      if messages.any?
        message_string = messages.map { |m| m[:payload].inspect }.join("\n")
        min_hash_diff = messages.min_by { |m| _hash_diff(m, message)&.keys&.size }
        diff = RSpec::Expectations.differ.diff_as_object(message, min_hash_diff[:payload])
      end
      printed_message = message.try(:to_h) || message
      str = "Expected #{topic} #{'not ' if was_negated}to have sent #{printed_message}"
      str += " with key #{key}" if key
      str += " with partition key #{partition_key}" if partition_key
      str += "\nClosest message received: #{min_hash_diff}" if min_hash_diff
      str += "\nDiff: #{diff}" if diff
      str + "\nAll Messages received:\n#{message_string}"
    end

    RSpec::Matchers.define :have_sent do |msg, key=nil, partition_key=nil, headers=nil|
      message = Deimos::TestHelpers.normalize_message(msg)
      match do |topic|
        message_key = Deimos::TestHelpers.normalize_message(key)
        hash_matcher = RSpec::Matchers::BuiltIn::Match.new(message)
        Deimos::TestHelpers.sent_messages.any? do |m|
          return m[:payload] == message if message.is_a?(String)

          message.delete(:payload_key) if message.respond_to?(:[]) && message[:payload_key].nil?
          if m.respond_to?(:[]) && m[:payload].respond_to?(:[]) && m[:payload][:payload_key].nil?
            m[:payload].delete(:payload_key)
          end
          hash_matcher.send(:match, message, m[:payload]) &&
            topic == m[:topic] &&
            (key.present? ? message_key == m[:key] : true) &&
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
      puts '[Deprecated] clear_kafka_messages! can be replaced with' \
           '`karafka.produced_messages.clear`'
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
                             call_original: nil,
                             partition_key: nil,
                             &block)
      unless call_original.nil?
        puts 'test_consume_message(call_original: true) is deprecated and will be removed' \
             'in the future. You can remove the call_original parameter.'
      end
      test_consume_batch(handler_class_or_topic,
                         [payload],
                         keys: [key],
                         partition_keys: [partition_key],
                         single: true,
                         &block)
    end

    # Test that a given handler will consume a given batch payload correctly,
    # i.e. that the schema is correct. If
    # a block is given, that block will be executed when `consume` is called.
    # Otherwise it will just confirm that `consume` is called at all.
    # @param handler_class_or_topic [Class, String] Class which inherits from
    # Deimos::Consumer or the topic as a string
    # @param payloads [Array<Hash>] the payload to consume
    # @param call_original [Boolean,nil] legacy parameter.
    # @param keys [Array<Object>]
    # @param partition_keys [Array<Object>]
    # @param single [Boolean] used internally.
    # @return [void]
    def test_consume_batch(handler_class_or_topic,
                           payloads,
                           keys: [],
                           call_original: nil,
                           single: false,
                           partition_keys: [])
      unless call_original.nil?
        puts 'test_consume_batch(call_original: true) is deprecated and will be removed' \
             'in the future. You can remove the call_original parameter.'
      end
      karafka.consumer_messages.clear
      topic_name = if handler_class_or_topic.is_a?(String)
        handler_class_or_topic
                   else
        Deimos.topic_for_consumer(handler_class_or_topic)
      end
      consumer = karafka.consumer_for(topic_name)

      Deimos.karafka_config_for(topic: topic_name).each_message(single)

      # don't record messages sent with test_consume_batch
      original_messages = karafka.produced_messages.dup
      payloads.each_with_index do |payload, i|
       karafka.produce(payload, { key: keys[i], partition_key: partition_keys[i], topic: consumer.topic.name })
      end
      if block_given?
        if single
          allow(consumer).to receive(:consume_message) do
           yield(consumer.messages.first.payload, consumer.messages.first.as_json['metadata'])
          end
        else
          allow(consumer).to receive(:consume_batch) do
           yield(consumer.messages)
          end
        end
      end

      # sent_messages should only include messages sent by application code, not this method
      karafka.produced_messages.clear
      karafka.produced_messages.concat(original_messages)

      consumer.consume
    end
  end
end
