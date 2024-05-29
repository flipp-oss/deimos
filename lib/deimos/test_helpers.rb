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
    end

    # @param client [Karafka::Testing::RSpec::Proxy]
    # @return [Array<Hash>]
    def sent_messages(client=nil)
      self.class.sent_messages(client)
    end

    class << self
      # @param client [Karafka::Testing::RSpec::Proxy]
      # @return [Array<Hash>]
      def sent_messages(client=nil)
        (client || karafka).produced_messages.map do |m|
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
        Deimos.configure do |deimos_config|
          deimos_config.logger = Logger.new(STDOUT)
          deimos_config.consumers.reraise_errors = true
          deimos_config.schema.backend = :avro_local
          deimos_config.producers.backend = :test
        end
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
    def _frk_failure_message(client, topic, message, key=nil, partition_key=nil, was_negated=false)
      messages = Deimos::TestHelpers.sent_messages(client).select { |m| m[:topic] == topic }
      message_string = ''
      diff = nil
      min_hash_diff = nil
      message = Deimos::TestHelpers.normalize_message(message)
      if messages.any?
        message_string = messages.map { |m| m[:payload].inspect}.join("\n")
        min_hash_diff = messages.min_by { |m| _hash_diff(m, message)&.keys&.size }
        diff = RSpec::Expectations.differ.diff_as_object(message, min_hash_diff[:payload])
      end
      str = "Expected #{topic} #{'not ' if was_negated}to have sent #{message.try(:to_h) || message}"
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
        Deimos::TestHelpers.sent_messages(karafka).any? do |m|
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
        _frk_failure_message(karafka, topic, message, key, partition_key)
      end
      failure_message_when_negated do |topic|
        _frk_failure_message(karafka, topic, message, key, partition_key, true)
      end
    end

    # Clear all sent messages - e.g. if we want to check that
    # particular messages were sent or not sent after a point in time.
    # @return [void]
    def clear_kafka_messages!
      puts "[Deprecated] clear_kafka_messages! can be replaced with `karafka.produced_messages.clear`"
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
                             call_original: Karafka::Routing::Default.new(nil),
                             partition_key: nil)
      unless call_original.is_a?(Karafka::Routing::Default)
        puts "test_consume_message(call_original: true) is deprecated and will be removed in the future. You can remove the call_original parameter."
      end
      test_consume_batch(handler_class_or_topic, [payload], keys: [key], partition_keys: [partition_key], single: true)
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
    # @param single [Boolean] used internally.
    # @return [void]
    def test_consume_batch(handler_class_or_topic,
                           payloads,
                           keys: [],
                           call_original: Karafka::Routing::Default.new(nil),
                           single: false,
                           partition_keys: [])
      unless call_original.is_a?(Karafka::Routing::Default)
        puts "test_consume_batch(call_original: true) is deprecated and will be removed in the future. You can remove the call_original parameter."
      end
      consumer = nil
      topic_name = nil
      if handler_class_or_topic.is_a?(String)
        topic_name = handler_class_or_topic
        consumer = karafka.consumer_for(topic_name)
      else
        topic_name = Deimos.topic_for_consumer(handler_class_or_topic)
        consumer = karafka.consumer_for(topic_name)
      end

      Deimos.karafka_config_for(topic: topic_name).batch(!single)

       payloads.each_with_index do |payload, i|
         karafka.produce(payload, {key: keys[i], partition_key: partition_keys[i], topic: consumer.topic.name})
       end
       if block_given?
         allow_any_instance_of(consumer_class).to receive(:consume_batch) do
           yield
         end
       end
       consumer.consume
      end
  end
end
