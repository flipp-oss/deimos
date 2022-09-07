# frozen_string_literal: true

require 'deimos/message'
require 'deimos/shared_config'
require 'phobos/producer'
require 'active_support/notifications'

# :nodoc:
module Deimos
  class << self
    # Run a block without allowing any messages to be produced to Kafka.
    # Optionally add a list of producer classes to limit the disabling to those
    # classes.
    # @param producer_classes [Array<Class>, Class]
    # @return [void]
    def disable_producers(*producer_classes, &block)
      if producer_classes.any?
        _disable_producer_classes(producer_classes, &block)
        return
      end

      if Thread.current[:frk_disable_all_producers] # nested disable block
        yield
        return
      end

      begin
        Thread.current[:frk_disable_all_producers] = true
        yield
      ensure
        Thread.current[:frk_disable_all_producers] = false
      end
    end

    # @!visibility private
    def _disable_producer_classes(producer_classes)
      Thread.current[:frk_disabled_producers] ||= Set.new
      producers_to_disable = producer_classes -
                             Thread.current[:frk_disabled_producers].to_a
      Thread.current[:frk_disabled_producers] += producers_to_disable
      yield
      Thread.current[:frk_disabled_producers] -= producers_to_disable
    end

    # Are producers disabled? If a class is passed in, check only that class.
    # Otherwise check if the global disable flag is set.
    # @param producer_class [Class]
    # @return [Boolean]
    def producers_disabled?(producer_class=nil)
      Thread.current[:frk_disable_all_producers] ||
        Thread.current[:frk_disabled_producers]&.include?(producer_class)
    end
  end

  # Producer to publish messages to a given kafka topic.
  class Producer
    include SharedConfig

    # @return [Integer]
    MAX_BATCH_SIZE = 500

    class << self

      # @return [Hash]
      def config
        @config ||= {
          encode_key: true,
          namespace: Deimos.config.producers.schema_namespace
        }
      end

      # Set the topic.
      # @param topic [String]
      # @return [String] the current topic if no argument given.
      def topic(topic=nil)
        if topic
          config[:topic] = topic
          return
        end
        # accessor
        "#{Deimos.config.producers.topic_prefix}#{config[:topic]}"
      end

      # Override the default partition key (which is the payload key).
      # @param _payload [Hash] the payload being passed into the produce method.
      # Will include `payload_key` if it is part of the original payload.
      # @return [String]
      def partition_key(_payload)
        nil
      end

      # Publish the payload to the topic.
      # @param payload [Hash, SchemaClass::Record] with an optional payload_key hash key.
      # @param topic [String] if specifying the topic
      # @return [void]
      def publish(payload, topic: self.topic)
        publish_list([payload], topic: topic)
      end

      # Publish a list of messages.
      # @param payloads [Array<Hash, SchemaClass::Record>] with optional payload_key hash key.
      # @param sync [Boolean] if given, override the default setting of
      # whether to publish synchronously.
      # @param force_send [Boolean] if true, ignore the configured backend
      # and send immediately to Kafka.
      # @param topic [String] if specifying the topic
      # @return [void]
      def publish_list(payloads, sync: nil, force_send: false, topic: self.topic)
        return if Deimos.config.kafka.seed_brokers.blank? ||
                  Deimos.config.producers.disabled ||
                  Deimos.producers_disabled?(self)

        raise 'Topic not specified. Please specify the topic.' if topic.blank?

        backend_class = determine_backend_class(sync, force_send)
        Deimos.instrument(
          'encode_messages',
          producer: self,
          topic: topic,
          payloads: payloads
        ) do
          messages = Array(payloads).map { |p| Deimos::Message.new(p.to_h, self) }
          messages.each { |m| _process_message(m, topic) }
          messages.in_groups_of(MAX_BATCH_SIZE, false) do |batch|
            self.produce_batch(backend_class, batch)
          end
        end
      end

      # @param sync [Boolean]
      # @param force_send [Boolean]
      # @return [Class<Deimos::Backends::Base>]
      def determine_backend_class(sync, force_send)
        backend = if force_send
                    :kafka
                  else
                    Deimos.config.producers.backend
                  end
        if backend == :kafka_async && sync
          backend = :kafka
        elsif backend == :kafka && sync == false
          backend = :kafka_async
        end
        "Deimos::Backends::#{backend.to_s.classify}".constantize
      end

      # Send a batch to the backend.
      # @param backend [Class<Deimos::Backends::Base>]
      # @param batch [Array<Deimos::Message>]
      # @return [void]
      def produce_batch(backend, batch)
        backend.publish(producer_class: self, messages: batch)
      end

      # @return [Deimos::SchemaBackends::Base]
      def encoder
        @encoder ||= Deimos.schema_backend(schema: config[:schema],
                                           namespace: config[:namespace])
      end

      # @return [Deimos::SchemaBackends::Base]
      def key_encoder
        @key_encoder ||= Deimos.schema_backend(schema: config[:key_schema],
                                               namespace: config[:namespace])
      end

      # Override this in active record producers to add
      # non-schema fields to check for updates
      # @return [Array<String>] fields to check for updates
      def watched_attributes
        self.encoder.schema_fields.map(&:name)
      end

    private

      # @param message [Message]
      # @param topic [String]
      def _process_message(message, topic)
        # this violates the Law of Demeter but it has to happen in a very
        # specific order and requires a bunch of methods on the producer
        # to work correctly.
        message.add_fields(encoder.schema_fields.map(&:name))
        message.partition_key = self.partition_key(message.payload)
        message.key = _retrieve_key(message.payload)
        # need to do this before _coerce_fields because that might result
        # in an empty payload which is an *error* whereas this is intended.
        message.payload = nil if message.payload.blank?
        message.coerce_fields(encoder)
        message.encoded_key = _encode_key(message.key)
        message.topic = topic
        message.encoded_payload = if message.payload.nil?
                                    nil
                                  else
                                    encoder.encode(message.payload,
                                                   topic: "#{Deimos.config.producers.topic_prefix}#{config[:topic]}-value")
                                  end
      end

      # @param key [Object]
      # @return [String|Object]
      def _encode_key(key)
        if key.nil?
          return nil if config[:no_keys] # no key is fine, otherwise it's a problem

          raise 'No key given but a key is required! Use `key_config none: true` to avoid using keys.'
        end
        if config[:encode_key] && config[:key_field].nil? &&
           config[:key_schema].nil?
          raise 'No key config given - if you are not encoding keys, please use `key_config plain: true`'
        end

        if config[:key_field]
          encoder.encode_key(config[:key_field], key, topic: "#{Deimos.config.producers.topic_prefix}#{config[:topic]}-key")
        elsif config[:key_schema]
          key_encoder.encode(key, topic: "#{Deimos.config.producers.topic_prefix}#{config[:topic]}-key")
        else
          key
        end
      end

      # @param payload [Hash]
      # @return [String]
      def _retrieve_key(payload)
        key = payload.delete(:payload_key)
        return key if key

        config[:key_field] ? payload[config[:key_field]] : nil
      end
    end
  end
end
