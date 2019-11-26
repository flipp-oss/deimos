# frozen_string_literal: true

require 'active_support/concern'
require 'active_support/core_ext'
require 'avro_turf'
require 'deimos/tracing/mock'
require 'deimos/metrics/mock'

module Deimos
  # Include this module in your RSpec spec_helper
  # to stub out external dependencies
  # and add methods to use to test encoding/decoding.
  module TestHelpers
    extend ActiveSupport::Concern

    class << self
      # @return [Array<Hash>]
      def sent_messages
        @sent_messages ||= []
      end
    end

    included do
      # @param encoder_schema [String]
      # @param namespace [String]
      # @return [Deimos::AvroDataEncoder]
      def create_encoder(encoder_schema, namespace)
        encoder = Deimos::AvroDataEncoder.new(schema: encoder_schema,
                                              namespace: namespace)

        # we added and_wrap_original to RSpec 2 but the regular block
        # syntax wasn't working for some reason - block wasn't being passed
        # to the method
        block = proc do |m, *args|
          m.call(*args)
          args[0]
        end
        allow(encoder).to receive(:encode_local).and_wrap_original(&block)
        allow(encoder).to receive(:encode) do |payload, schema: nil, topic: nil|
          encoder.encode_local(payload, schema: schema)
        end

        block = proc do |m, *args|
          m.call(*args)&.values&.first
        end
        allow(encoder).to receive(:encode_key).and_wrap_original(&block)
        encoder
      end

      # @param decoder_schema [String]
      # @param namespace [String]
      # @return [Deimos::AvroDataDecoder]
      def create_decoder(decoder_schema, namespace)
        decoder = Deimos::AvroDataDecoder.new(schema: decoder_schema,
                                              namespace: namespace)
        allow(decoder).to receive(:decode_local) { |payload| payload }
        allow(decoder).to receive(:decode) do |payload, schema: nil|
          schema ||= decoder.schema
          if schema && decoder.namespace
            # Validate against local schema.
            encoder = Deimos::AvroDataEncoder.new(schema: schema,
                                                  namespace: decoder.namespace)
            encoder.schema_store = decoder.schema_store
            payload = payload.respond_to?(:stringify_keys) ? payload.stringify_keys : payload
            encoder.encode_local(payload)
          end
          payload
        end
        allow(decoder).to receive(:decode_key) do |payload, _key_id|
          payload.values.first
        end
        decoder
      end

      RSpec.configure do |config|

        config.before(:suite) do
          Deimos.configure do |fr_config|
            fr_config.logger = Logger.new(STDOUT)
            fr_config.consumers.reraise_errors = true
            fr_config.kafka.seed_brokers ||= ['test_broker']
          end
        end

      end
      before(:each) do
        client = double('client').as_null_object
        allow(client).to receive(:time) do |*_args, &block|
          block.call
        end
      end
    end

    # Stub all already-loaded producers and consumers for unit testing purposes.
    def stub_producers_and_consumers!
      Deimos::TestHelpers.sent_messages.clear

      allow(Deimos::Producer).to receive(:produce_batch) do |_, batch|
        Deimos::TestHelpers.sent_messages.concat(batch.map(&:to_h))
      end

      Deimos::Producer.descendants.each do |klass|
        next if klass == Deimos::ActiveRecordProducer # "abstract" class

        stub_producer(klass)
      end

      Deimos::Consumer.descendants.each do |klass|
        # TODO: remove this when ActiveRecordConsumer uses batching
        next if klass == Deimos::ActiveRecordConsumer # "abstract" class

        stub_consumer(klass)
      end

      Deimos::BatchConsumer.descendants.each do |klass|
        next if klass == Deimos::ActiveRecordConsumer # "abstract" class

        stub_batch_consumer(klass)
      end
    end

    # Stub a given producer class.
    # @param klass [Class < Deimos::Producer]
    def stub_producer(klass)
      allow(klass).to receive(:encoder) do
        create_encoder(klass.config[:schema], klass.config[:namespace])
      end
      allow(klass).to receive(:key_encoder) do
        create_encoder(klass.config[:key_schema], klass.config[:namespace])
      end
    end

    # Stub a given consumer class.
    # @param klass [Class < Deimos::Consumer]
    def stub_consumer(klass)
      _stub_base_consumer(klass)
      klass.class_eval do
        alias_method(:old_consume, :consume) unless self.instance_methods.include?(:old_consume)
      end
      allow_any_instance_of(klass).to receive(:consume) do |instance, payload, metadata|
        metadata[:key] = klass.new.decode_key(metadata[:key]) if klass.config[:key_configured]
        instance.old_consume(payload, metadata)
      end
    end

    # Stub a given batch consumer class.
    # @param klass [Class < Deimos::BatchConsumer]
    def stub_batch_consumer(klass)
      _stub_base_consumer(klass)
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
      messages = Deimos::TestHelpers.sent_messages.
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
        Deimos::TestHelpers.sent_messages.any? do |m|
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
      Deimos::TestHelpers.sent_messages.clear
    end

    # test that a message was sent on the given topic.
    # DEPRECATED - use the "have_sent" matcher instead.
    # @param message [Hash]
    # @param topic [String]
    # @param key [String|Integer]
    # @return [Boolean]
    def was_message_sent?(message, topic, key=nil)
      Deimos::TestHelpers.sent_messages.any? do |m|
        message == m[:payload] && m[:topic] == topic &&
          (key.present? ? m[:key] == key : true)
      end
    end

    # Test that a given handler will consume a given payload correctly, i.e.
    # that the Avro schema is correct. If
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

    # Check to see that a given message will fail due to Avro errors.
    # @param handler_class [Class]
    # @param payload [Hash]
    def test_consume_invalid_message(handler_class, payload)
      handler = handler_class.new
      allow(handler_class).to receive(:new).and_return(handler)
      listener = double('listener',
                        handler_class: handler_class,
                        encoding: nil)
      message = double('message',
                       key: _key_from_consumer(handler_class),
                       partition_key: nil,
                       partition: 1,
                       offset: 1,
                       value: payload)

      expect {
        Phobos::Actions::ProcessMessage.new(
          listener: listener,
          message: message,
          listener_metadata: { topic: 'my-topic' }
        ).send(:process_message, payload)
      }.to raise_error(Avro::SchemaValidator::ValidationError)
    end

    # Test that a given handler will consume a given batch payload correctly,
    # i.e. that the Avro schema is correct. If
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

    # Check to see that a given message will fail due to Avro errors.
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
        to raise_error(Avro::SchemaValidator::ValidationError)
    end

    # @param schema1 [String|Hash] a file path, JSON string, or
    # hash representing a schema.
    # @param schema2 [String|Hash] a file path, JSON string, or
    # hash representing a schema.
    # @return [Boolean] true if the schemas are compatible, false otherwise.
    def self.schemas_compatible?(schema1, schema2)
      json1, json2 = [schema1, schema2].map do |schema|
        if schema.is_a?(String)
          schema = File.read(schema) unless schema.strip.starts_with?('{') # file path
          MultiJson.load(schema)
        else
          schema
        end
      end
      avro_schema1 = Avro::Schema.real_parse(json1, {})
      avro_schema2 = Avro::Schema.real_parse(json2, {})
      Avro::SchemaCompatibility.mutual_read?(avro_schema1, avro_schema2)
    end

  private

    def _key_from_consumer(consumer)
      if consumer.config[:key_field] || consumer.config[:key_schema]
        { 'test' => 1 }
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

    # Stub shared methods between consumers/batch consumers
    # @param [Class < Deimos::BaseConsumer] klass Consumer class to stub
    def _stub_base_consumer(klass)
      allow(klass).to receive(:decoder) do
        create_decoder(klass.config[:schema], klass.config[:namespace])
      end

      if klass.config[:key_schema] # rubocop:disable Style/GuardClause
        allow(klass).to receive(:key_decoder) do
          create_decoder(klass.config[:key_schema], klass.config[:namespace])
        end
      end
    end
  end
end
