# frozen_string_literal: true

# Class to consume messages. Can be used with integration testing frameworks.
# Assumes that you have a topic with only one partition.
module Deimos
  module Utils
    # Listener that can seek to get the last X messages in a topic.
    class SeekListener < Phobos::Listener
      # @return [Integer]
      MAX_SEEK_RETRIES = 3
      # @return [Integer]
      attr_accessor :num_messages

      # @return [void]
      def start_listener
        @num_messages ||= 10
        @consumer = create_kafka_consumer
        @consumer.subscribe(topic, @subscribe_opts)
        attempt = 0

        begin
          attempt += 1
          last_offset = @kafka_client.last_offset_for(topic, 0)
          offset = last_offset - num_messages
          if offset.positive?
            Deimos.config.logger.info("Seeking to #{offset}")
            @consumer.seek(topic, 0, offset)
          end
        rescue StandardError => e
          if attempt < MAX_SEEK_RETRIES
            sleep(1.seconds * attempt)
            retry
          end
          log_error("Could not seek to offset: #{e.message} after #{MAX_SEEK_RETRIES} retries", listener_metadata)
        end

        instrument('listener.start_handler', listener_metadata) do
          @handler_class.start(@kafka_client)
        end
        log_info('Listener started', listener_metadata)
      end
    end

    # Class to return the messages consumed.
    class MessageBankHandler < Deimos::Consumer
      include Phobos::Handler

      cattr_accessor :total_messages

      # @param klass [Class<Deimos::Consumer>]
      # @return [void]
      def self.config_class=(klass)
        self.config.merge!(klass.config)
      end

      # @param _kafka_client [Kafka::Client]
      # @return [void]
      def self.start(_kafka_client)
        self.total_messages = []
      end

      # @param payload [Hash]
      # @param metadata [Hash]
      def consume(payload, metadata)
        self.class.total_messages << {
          key: metadata[:key],
          payload: payload
        }
      end
    end

    # Class which can process/consume messages inline.
    class InlineConsumer
      # @return [Integer]
      MAX_MESSAGE_WAIT_TIME = 1.second
      # @return [Integer]
      MAX_TOPIC_WAIT_TIME = 10.seconds

      # Get the last X messages from a topic. You can specify a subclass of
      # Deimos::Consumer or Deimos::Producer, or provide the
      # schema, namespace and key_config directly.
      # @param topic [String]
      # @param config_class [Class<Deimos::Consumer>,Class<Deimos::Producer>]
      # @param schema [String]
      # @param namespace [String]
      # @param key_config [Hash]
      # @param num_messages [Integer]
      # @return [Array<Hash>]
      def self.get_messages_for(topic:, schema: nil, namespace: nil, key_config: nil,
                                config_class: nil, num_messages: 10)
        if config_class
          MessageBankHandler.config_class = config_class
        elsif schema.nil? || key_config.nil?
          raise 'You must specify either a config_class or a schema, namespace and key_config!'
        else
          MessageBankHandler.class_eval do
            schema schema
            namespace namespace
            key_config key_config
            @decoder = nil
            @key_decoder = nil
          end
        end
        self.consume(topic: topic,
                     frk_consumer: MessageBankHandler,
                     num_messages: num_messages)
        messages = MessageBankHandler.total_messages
        messages.size <= num_messages ? messages : messages[-num_messages..-1]
      end

      # Consume the last X messages from a topic.
      # @param topic [String]
      # @param frk_consumer [Class]
      # @param num_messages [Integer] If this number is >= the number
      #   of messages in the topic, all messages will be consumed.
      # @return [void]
      def self.consume(topic:, frk_consumer:, num_messages: 10)
        listener = SeekListener.new(
          handler: frk_consumer,
          group_id: SecureRandom.hex,
          topic: topic,
          heartbeat_interval: 1
        )
        listener.num_messages = num_messages

        # Add the start_time and last_message_time attributes to the
        # consumer class so we can kill it if it's gone on too long
        class << frk_consumer
          attr_accessor :start_time, :last_message_time
        end

        subscribers = []
        subscribers << ActiveSupport::Notifications.
          subscribe('phobos.listener.process_message') do
            frk_consumer.last_message_time = Time.zone.now
        end
        subscribers << ActiveSupport::Notifications.
          subscribe('phobos.listener.start_handler') do
            frk_consumer.start_time = Time.zone.now
            frk_consumer.last_message_time = nil
        end
        subscribers << ActiveSupport::Notifications.
          subscribe('heartbeat.consumer.kafka') do
            if frk_consumer.last_message_time
              if Time.zone.now - frk_consumer.last_message_time > MAX_MESSAGE_WAIT_TIME
                raise Phobos::AbortError
              end
            elsif Time.zone.now - frk_consumer.start_time > MAX_TOPIC_WAIT_TIME
              Deimos.config.logger.error('Aborting - initial wait too long')
              raise Phobos::AbortError
            end
        end
        listener.start
        subscribers.each { |s| ActiveSupport::Notifications.unsubscribe(s) }
      end
    end
  end
end
