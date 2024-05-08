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
        Deimos::Backends::Test.sent_messages
      end

      # Set the config to the right settings for a unit test
      # @return [void]
      def unit_test!
        Deimos.configure do |deimos_config|
          deimos_config.logger = Logger.new(STDOUT)
          deimos_config.consumers.reraise_errors = true
          deimos_config.kafka.seed_brokers ||= ['test_broker']
          deimos_config.schema.backend = Deimos.schema_backend_class.mock_backend
          deimos_config.producers.backend = :test
          deimos_config.tracer = Deimos::Tracing::Mock.new
        end
      end

      # Kafka test config with avro schema registry
      # @return [void]
      def full_integration_test!
        Deimos.configure do |deimos_config|
          deimos_config.producers.backend = :kafka
          deimos_config.schema.backend = :avro_schema_registry
        end
      end

      # Set the config to the right settings for a kafka test
      # @return [void]
      def kafka_test!
        Deimos.configure do |deimos_config|
          deimos_config.producers.backend = :kafka
          deimos_config.schema.backend = :avro_validation
        end
      end
    end

    included do

      RSpec.configure do |config|
        config.prepend_before(:each) do
          client = double('client').as_null_object
          allow(client).to receive(:time) do |*_args, &block|
            block.call
          end
          Deimos::Backends::Test.sent_messages.clear
        end
      end

    end

    # get the difference of 2 hashes.
    # @param hash1 [Hash]
    # @param hash2 [Hash]
    # @!visibility private
    def _hash_diff(hash1, hash2)
      if hash1.nil? || !hash1.is_a?(Hash)
        hash2
      elsif hash2.nil? || !hash2.is_a?(Hash)
        hash1
      else
        hash1.dup.
          delete_if { |k, v| hash2[k] == v }.
          merge!(hash2.dup.delete_if { |k, _v| hash1.key?(k) })
      end
    end

    # @!visibility private
    def _frk_failure_message(topic, message, key=nil, partition_key=nil, was_negated=false)
      messages = Deimos::Backends::Test.sent_messages.
        select { |m| m[:topic] == topic }.
        map { |m| m.except(:topic) }
      message_string = ''
      diff = nil
      min_hash_diff = nil
      if messages.any?
        message_string = messages.map(&:inspect).join("\n")
        min_hash_diff = messages.min_by { |m| _hash_diff(m, message).keys.size }
        diff = RSpec::Expectations.differ.
          diff_as_object(message, min_hash_diff[:payload])
      end
      description = if message.respond_to?(:description)
                      message.description
                    elsif message.nil?
                      'nil'
                    else
                      message
                    end
      str = "Expected #{topic} #{'not ' if was_negated}to have sent #{description}"
      str += " with key #{key}" if key
      str += " with partition key #{partition_key}" if partition_key
      str += "\nClosest message received: #{min_hash_diff}" if min_hash_diff
      str += "\nDiff: #{diff}" if diff
      str + "\nAll Messages received:\n#{message_string}"
    end

    RSpec::Matchers.define :have_sent do |msg, key=nil, partition_key=nil, headers=nil|
      message = if msg.respond_to?(:with_indifferent_access)
                  msg.with_indifferent_access
                else
                  msg
                end
      match do |topic|
        Deimos::Backends::Test.sent_messages.any? do |m|
          hash_matcher = RSpec::Matchers::BuiltIn::Match.new(message)
          hash_matcher.send(:match,
                            message&.respond_to?(:to_h) ? message.to_h : message,
                            m[:payload]&.with_indifferent_access) &&
            topic == m[:topic] &&
            (key.present? ? key == m[:key] : true) &&
            (partition_key.present? ? partition_key == m[:partition_key] : true) &&
            if headers.present?
              hash_matcher.send(:match,
                                headers&.with_indifferent_access,
                                m[:headers]&.with_indifferent_access)
            else
              true
            end
        end
      end

      if respond_to?(:failure_message)
        failure_message do |topic|
          _frk_failure_message(topic, message, key, partition_key)
        end
        failure_message_when_negated do |topic|
          _frk_failure_message(topic, message, key, partition_key, true)
        end
      else
        failure_message_for_should do |topic|
          _frk_failure_message(topic, message, key, partition_key)
        end
        failure_message_for_should_not do |topic|
          _frk_failure_message(topic, message, key, partition_key, true)
        end
      end
    end

    # Clear all sent messages - e.g. if we want to check that
    # particular messages were sent or not sent after a point in time.
    # @return [void]
    def clear_kafka_messages!
      Deimos::Backends::Test.sent_messages.clear
    end

    # Test that a given handler will consume a given payload correctly, i.e.
    # that the schema is correct. If
    # a block is given, that block will be executed when `consume` is called.
    # Otherwise it will just confirm that `consume` is called at all.
    # @param handler_class_or_topic [Class, String] Class which inherits from
    # Deimos::Consumer or the topic as a string
    # @param payload [Hash] the payload to consume
    # @param call_original [Boolean] if true, allow the consume handler
    # to continue as normal. Not compatible with a block.
    # @param skip_expectation [Boolean] Set to true to not place any
    # expectations on the consumer. Primarily used internally to Deimos.
    # @param key [Object] the key to use.
    # @param partition_key [Object] the partition key to use.
    # @return [void]
    def test_consume_message(handler_class_or_topic,
                             payload,
                             call_original: :not_given,
                             key: nil,
                             partition_key: nil,
                             skip_expectation: :not_given,
                             &block)

      if call_original != :not_given
        puts "test_consume_message(call_original: true) is deprecated and no longer used."
      end
      if skip_expectation != :not_given
        puts "test_consume_message(skip_expectation: true) is deprecated and no longer used."
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
    # @param keys [Array<Hash,String>]
    # @param partition_keys [Array<Integer>]
    # @param call_original [Boolean]
    # @param skip_expectation [Boolean]
    # @return [void]
    def test_consume_batch(handler_class_or_topic,
                           payloads,
                           keys: [],
                           partition_keys: [],
                           call_original: :not_given,
                           skip_expectation: :not_given,
                           &block)
      if call_original != :not_given
        puts "test_consume_message(call_original: true) is deprecated and no longer used."
      end
      if skip_expectation != :not_given
        puts "test_consume_message(skip_expectation: true) is deprecated and no longer used."
      end

      topic_name = nil
      consumer = nil
      handler_class = nil
      if handler_class_or_topic.is_a?(String)
        topic_name = handler_class_or_topic
        consumer = karafka.consumer_for(topic_name)
        handler_class = consumer.coordinator.topic.consumer
      else
        handler_class = handler_class_or_topic
        topic_name = Deimos.topic_for_consumer(handler_class_or_topic)

        unless topic_name
          topic_name = SecureRandom.hex
          KarafkaApp.routes.clear
          KarafkaApp.routes.draw do
            topic topic_name.to_sym do
              consumer handler_class_or_topic
            end
          end
        end

        consumer = karafka.consumer_for(topic_name)
      end
      messages = payloads.map.with_index do |payload, i|
        key = keys[i]
        key ||= _key_from_consumer(handler_class)
        payload.stringify_keys! if payload.respond_to?(:stringify_keys!)

        metadata = Karafka::Messages::Metadata.new({
                                                     raw_key: key,
                                                     deserializers: consumer.topic.deserializers,
                                                     timestamp: Time.zone.now,
                                                     topic: consumer.topic.name,
                                                     partition: 1,
                                                     offset: payloads.size,
                                                     raw_headers: {}
                                                   })
        Karafka::Messages::Message.new(payload, metadata)
      end
      batch_metadata = Karafka::Messages::Builders::BatchMetadata.call(
        messages,
        consumer.topic,
        0,
        Time.now
      )
      consumer.messages = Karafka::Messages::Messages.new(
        messages,
        batch_metadata
      )
      consumer.consume
    end

  private

    def _key_from_consumer(consumer)
      if consumer.config[:key_field]
        { consumer.config[:key_field] => 1 }
      elsif consumer.config[:key_schema]
        backend = consumer.decoder
        old_schema = backend.schema
        backend.schema = consumer.config[:key_schema]
        key = backend.schema_fields.map { |field| [field.name, 1] }.to_h
        backend.schema = old_schema
        key
      elsif consumer.config[:no_keys]
        nil
      else
        1
      end
    end
  end
end
