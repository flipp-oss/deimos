# frozen_string_literal: true

require 'deimos/message'
require 'deimos/shared_config'
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
      begin
        Thread.current[:frk_disabled_producers] += producers_to_disable
        yield
      ensure
        Thread.current[:frk_disabled_producers] -= producers_to_disable
      end
    end

    # Are producers disabled? If a class is passed in, check only that class.
    # Otherwise check if the global disable flag is set.
    # @param producer_class [Class]
    # @return [Boolean]
    def producers_disabled?(producer_class=nil)
      return true if Deimos.config.producers.disabled

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
      # @param headers [Hash] if specifying headers
      # @return [void]
      def publish(payload, topic: self.topic, headers: nil)
        publish_list([payload], topic: topic, headers: headers)
      end

      # Publish a list of messages.
      # @param payloads [Array<Hash, SchemaClass::Record>] with optional payload_key hash key.
      # @param sync [Boolean] if given, override the default setting of
      # whether to publish synchronously.
      # @param force_send [Boolean] if true, ignore the configured backend
      # and send immediately to Kafka.
      # @param topic [String] if specifying the topic
      # @param headers [Hash] if specifying headers
      # @return [void]
      def publish_list(payloads, sync: nil, force_send: false, topic: self.topic, headers: nil)
        return if Deimos.producers_disabled?(self)

        backend_class = determine_backend_class(sync, force_send)
        Deimos.instrument(
          'encode_messages',
          producer: self,
          topic: topic,
          payloads: payloads
        ) do
          messages = Array(payloads).map do |p|
            {
              payload: p&.to_h,
              headers: headers,
              topic: topic,
              partition_key: self.partition_key(p)
            }
          end
          messages.each { |m| m[:label] = m }
          messages.in_groups_of(MAX_BATCH_SIZE, false) do |batch|
            self.produce_batch(backend_class, batch)
          end
        end
      end

      def karafka_config
        Deimos.karafka_configs.find { |topic| topic.producer_class == self }
      end

      def topic
        karafka_config.name
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

    end
  end
end
