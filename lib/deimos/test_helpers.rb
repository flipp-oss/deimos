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
    end

    included do

      RSpec.configure do |config|

        config.before(:suite) do
          Deimos.configure do |d_config|
            d_config.logger = Logger.new(STDOUT)
            d_config.consumers.reraise_errors = true
            d_config.kafka.seed_brokers ||= ['test_broker']
            d_config.schema.backend = Deimos.schema_backend_class.mock_backend
            d_config.producers.backend = :test
          end
        end

        config.prepend_before(:each) do
          client = double('client').as_null_object
          allow(client).to receive(:time) do |*_args, &block|
            block.call
          end
          Deimos::Backends::Test.sent_messages.clear
        end
      end

    end

    def configure_deimos(options)
      Deimos.configure do |d_config|
        options.each do |key, value|
          # If the config options are nested.
          # Assuming that there is only one level of nesting
          if value.is_a?(Hash)
            value.each do |k,v|
              d_config.send(key.to_sym).send(k.to_sym, v)
            end
          #  If the values are not nested, then simply assign them
          else
            d_config.send(key.to_sym, value)
          end
        end
        # d_config.logger = options[:logger] || Logger.new(STDOUT)
        # d_config.consumers.reraise_errors = options[:reraise_consumers_errors]
        # d_config.kafka.seed_brokers ||= options[:kafka_seed_brokers] || ['test_broker']
        # d_config.schema.backend = options[:schema_backend] || Deimos.schema_backend_class.mock_backend
        # d_config.producers.backend = options[:producers_backend] || :test
      end
    end

    # @deprecated
    def stub_producers_and_consumers!
      warn('stub_producers_and_consumers! is no longer necessary and this method will be removed in 3.0')
    end

    # @deprecated
    def stub_producer(_klass)
      warn('Stubbing producers is no longer necessary and this method will be removed in 3.0')
    end

    # @deprecated
    def stub_consumer(_klass)
      warn('Stubbing consumers is no longer necessary and this method will be removed in 3.0')
    end

    # @deprecated
    def stub_batch_consumer(_klass)
      warn('Stubbing batch consumers is no longer necessary and this method will be removed in 3.0')
    end

    # get the difference of 2 hashes.
    # @param hash1 [Hash]
    # @param hash2 [Hash]
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

    # :nodoc:
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

    RSpec::Matchers.define :have_sent do |msg, key=nil, partition_key=nil|
      message = if msg.respond_to?(:with_indifferent_access)
                  msg.with_indifferent_access
                else
                  msg
                end
      match do |topic|
        Deimos::Backends::Test.sent_messages.any? do |m|
          hash_matcher = RSpec::Matchers::BuiltIn::Match.new(message)
          hash_matcher.send(:match,
                            message,
                            m[:payload]&.with_indifferent_access) &&
            topic == m[:topic] &&
            (key.present? ? key == m[:key] : true) &&
            (partition_key.present? ? partition_key == m[:partition_key] : true)
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
    def clear_kafka_messages!
      Deimos::Backends::Test.sent_messages.clear
    end

    # Test that a given handler will consume a given payload correctly, i.e.
    # that the schema is correct. If
    # a block is given, that block will be executed when `consume` is called.
    # Otherwise it will just confirm that `consume` is called at all.
    # @param handler_class_or_topic [Class|String] Class which inherits from
    # Deimos::Consumer or the topic as a string
    # @param payload [Hash] the payload to consume
    # @param call_original [Boolean] if true, allow the consume handler
    # to continue as normal. Not compatible with a block.
    # @param ignore_expectation [Boolean] Set to true to not place any
    # expectations on the consumer. Primarily used internally to Deimos.
    # @param key [Object] the key to use.
    # @param partition_key [Object] the partition key to use.
    def test_consume_message(handler_class_or_topic,
                             payload,
                             call_original: false,
                             key: nil,
                             partition_key: nil,
                             skip_expectation: false,
                             &block)
      raise 'Cannot have both call_original and be given a block!' if call_original && block_given?

      payload&.stringify_keys!
      handler_class = if handler_class_or_topic.is_a?(String)
                        _get_handler_class_from_topic(handler_class_or_topic)
                      else
                        handler_class_or_topic
                      end
      handler = handler_class.new
      allow(handler_class).to receive(:new).and_return(handler)
      listener = double('listener',
                        handler_class: handler_class,
                        encoding: nil)
      key ||= _key_from_consumer(handler_class)
      message = double('message',
                       'key' => key,
                       'partition_key' => partition_key,
                       'partition' => 1,
                       'offset' => 1,
                       'headers' => {},
                       'value' => payload)

      unless skip_expectation
        expectation = expect(handler).to receive(:consume).
          with(payload, anything, &block)
        expectation.and_call_original if call_original
      end
      Phobos::Actions::ProcessMessage.new(
        listener: listener,
        message: message,
        listener_metadata: { topic: 'my-topic' }
      ).send(:process_message, payload)
    end

    # Check to see that a given message will fail due to validation errors.
    # @param handler_class [Class]
    # @param payload [Hash]
    def test_consume_invalid_message(handler_class, payload)
      expect {
        handler_class.decoder.validate(payload,
                                       schema: handler_class.decoder.schema)
      }.to raise_error(Avro::SchemaValidator::ValidationError)
    end

    # Test that a given handler will consume a given batch payload correctly,
    # i.e. that the schema is correct. If
    # a block is given, that block will be executed when `consume` is called.
    # Otherwise it will just confirm that `consume` is called at all.
    # @param handler_class_or_topic [Class|String] Class which inherits from
    # Deimos::Consumer or the topic as a string
    # @param payloads [Array<Hash>] the payload to consume
    def test_consume_batch(handler_class_or_topic,
                           payloads,
                           keys: [],
                           partition_keys: [],
                           call_original: false,
                           skip_expectation: false,
                           &block)
      if call_original && block_given?
        raise 'Cannot have both call_original and be given a block!'
      end

      topic_name = 'my-topic'
      handler_class = if handler_class_or_topic.is_a?(String)
                        _get_handler_class_from_topic(handler_class_or_topic)
                      else
                        handler_class_or_topic
                      end
      handler = handler_class.new
      allow(handler_class).to receive(:new).and_return(handler)
      listener = double('listener',
                        handler_class: handler_class,
                        encoding: nil)
      batch_messages = payloads.zip(keys, partition_keys).map do |payload, key, partition_key|
        key ||= _key_from_consumer(handler_class)

        double('message',
               'key' => key,
               'partition_key' => partition_key,
               'partition' => 1,
               'offset' => 1,
               'headers' => {},
               'value' => payload)
      end
      batch = double('fetched_batch',
                     'messages' => batch_messages,
                     'topic' => topic_name,
                     'partition' => 1,
                     'offset_lag' => 0)
      unless skip_expectation
        expectation = expect(handler).to receive(:consume_batch).
          with(payloads, anything, &block)
        expectation.and_call_original if call_original
      end
      action = Phobos::Actions::ProcessBatchInline.new(
        listener: listener,
        batch: batch,
        metadata: { topic: topic_name }
      )
      allow(action).to receive(:backoff_interval).and_return(0)
      allow(action).to receive(:handle_error) { |e| raise e }
      action.send(:execute)
    end

    # Check to see that a given message will fail due to validation errors.
    # @param handler_class [Class]
    # @param payloads [Array<Hash>]
    def test_consume_batch_invalid_message(handler_class, payloads)
      topic_name = 'my-topic'
      handler = handler_class.new
      allow(handler_class).to receive(:new).and_return(handler)
      listener = double('listener',
                        handler_class: handler_class,
                        encoding: nil)
      batch_messages = payloads.map do |payload|
        key ||= _key_from_consumer(handler_class)

        double('message',
               'key' => key,
               'partition' => 1,
               'offset' => 1,
               'value' => payload)
      end
      batch = double('fetched_batch',
                     'messages' => batch_messages,
                     'topic' => topic_name,
                     'partition' => 1,
                     'offset_lag' => 0)

      action = Phobos::Actions::ProcessBatchInline.new(
        listener: listener,
        batch: batch,
        metadata: { topic: topic_name }
      )
      allow(action).to receive(:backoff_interval).and_return(0)
      allow(action).to receive(:handle_error) { |e| raise e }

      expect { action.send(:execute) }.
        to raise_error
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

    # @param topic [String]
    # @return [Class]
    def _get_handler_class_from_topic(topic)
      listeners = Phobos.config['listeners']
      handler = listeners.find { |l| l.topic == topic }
      raise "No consumer found in Phobos configuration for topic #{topic}!" if handler.nil?

      handler.handler.constantize
    end
  end
end
