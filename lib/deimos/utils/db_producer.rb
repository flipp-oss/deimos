# frozen_string_literal: true

module Deimos
  module Utils
    # Class which continually polls the database and sends Kafka messages.
    class DbProducer
      include Phobos::Producer
      attr_accessor :id, :current_topic

      BATCH_SIZE = 1000

      # @param logger [Logger]
      def initialize(logger=Logger.new(STDOUT))
        @id = SecureRandom.uuid
        @logger = logger
        if @logger.respond_to?(:push_tags)
          @logger.push_tags("DbProducer #{@id}")
        end
      end

      # Start the poll.
      def start
        @logger.info('Starting...')
        @signal_to_stop = false
        loop do
          if @signal_to_stop
            @logger.info('Shutting down')
            break
          end
          process_next_messages
        end
      end

      # Stop the poll.
      def stop
        @logger.info('Received signal to stop')
        @signal_to_stop = true
      end

      # Complete one loop of processing all messages in the DB.
      def process_next_messages
        topics = retrieve_topics
        @logger.info("Found topics: #{topics}")
        topics.each(&method(:process_topic))
        sleep(0.5)
      end

      # @return [Array<String>]
      def retrieve_topics
        KafkaMessage.select('distinct topic').map(&:topic).uniq
      end

      # @param topic [String]
      # @return [String] the topic that was locked, or nil if none were.
      def process_topic(topic)
        # If the topic is already locked, another producer is currently
        # working on it. Move on to the next one.
        unless KafkaTopicInfo.lock(topic, @id)
          @logger.debug("Could not lock topic #{topic} - continuing")
          return
        end
        @current_topic = topic
        messages = retrieve_messages

        while messages.any?
          produce_messages(messages.map(&:phobos_message))
          messages.first.class.where(id: messages.map(&:id)).delete_all
          break if messages.size < BATCH_SIZE

          KafkaTopicInfo.heartbeat(@current_topic, @id) # keep alive
          messages = retrieve_messages
        end
        KafkaTopicInfo.clear_lock(@current_topic, @id)
      rescue StandardError => e
        @logger.error("Error processing messages for topic #{@current_topic}: #{e.class.name}: #{e.message} #{e.backtrace.join("\n")}")
        KafkaTopicInfo.register_error(@current_topic, @id)
      end

      # @return [Array<KafkaMessage>]
      def retrieve_messages
        KafkaMessage.where(topic: @current_topic).order(:id).limit(BATCH_SIZE)
      end

      # @param batch [Array<Hash>]
      def produce_messages(batch)
        @logger.debug("Publishing #{batch.size} messages to #{@current_topic}")
        producer.publish_list(batch)
        Deimos.metrics&.increment(
          'publish',
          tags: %W(status:success topic:#{@current_topic}),
          by: batch.size
        )
        @logger.info("Sent #{batch.size} messages to #{@current_topic}")
      end
    end
  end
end
