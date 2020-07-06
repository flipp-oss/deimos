# frozen_string_literal: true

module Deimos
  module Utils
    # Class which continually polls the kafka_messages table
    # in the database and sends Kafka messages.
    class DbProducer
      include Phobos::Producer
      attr_accessor :id, :current_topic

      BATCH_SIZE = 1000

      # @param logger [Logger]
      def initialize(logger=Logger.new(STDOUT))
        @id = SecureRandom.uuid
        @logger = logger
        @logger.push_tags("DbProducer #{@id}") if @logger.respond_to?(:push_tags)
      end

      # @return [Deimos::DbProducerConfig]
      def config
        Deimos.config.db_producer
      end

      # Start the poll.
      def start
        @logger.info('Starting...')
        @signal_to_stop = false
        ActiveRecord::Base.connection.reconnect!
        loop do
          if @signal_to_stop
            @logger.info('Shutting down')
            break
          end
          send_pending_metrics
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

        loop { break unless process_topic_batch }

        KafkaTopicInfo.clear_lock(@current_topic, @id)
      rescue StandardError => e
        @logger.error("Error processing messages for topic #{@current_topic}: #{e.class.name}: #{e.message} #{e.backtrace.join("\n")}")
        KafkaTopicInfo.register_error(@current_topic, @id)
      end

      # Process a single batch in a topic.
      def process_topic_batch
        messages = retrieve_messages
        return false if messages.empty?

        batch_size = messages.size
        compacted_messages = compact_messages(messages)
        log_messages(compacted_messages)
        Deimos.instrument('db_producer.produce', topic: @current_topic, messages: compacted_messages) do
          begin
            produce_messages(compacted_messages.map(&:phobos_message))
          rescue Kafka::BufferOverflow, Kafka::MessageSizeTooLarge, Kafka::RecordListTooLarge
            @logger.error('Message batch too large, deleting...')
            @logger.error(Deimos::KafkaMessage.decoded(messages))
            Deimos::KafkaMessage.where(id: messages.map(&:id)).delete_all
            raise
          end
        end
        Deimos::KafkaMessage.where(id: messages.map(&:id)).delete_all
        Deimos.config.metrics&.increment(
          'db_producer.process',
          tags: %W(topic:#{@current_topic}),
          by: messages.size
        )
        return false if batch_size < BATCH_SIZE

        KafkaTopicInfo.heartbeat(@current_topic, @id) # keep alive
        send_pending_metrics
        true
      end

      # @return [Array<Deimos::KafkaMessage>]
      def retrieve_messages
        KafkaMessage.where(topic: @current_topic).order(:id).limit(BATCH_SIZE)
      end

      # @param messages [Array<Deimos::KafkaMessage>]
      def log_messages(messages)
        return if config.log_topics != :all && !config.log_topics.include?(@current_topic)

        @logger.debug do
          decoded_messages = Deimos::KafkaMessage.decoded(messages)
          "DB producer: Topic #{@current_topic} Producing messages: #{decoded_messages}}"
        end
      end

      # Send metrics to Datadog.
      def send_pending_metrics
        metrics = Deimos.config.metrics
        return unless metrics

        messages = Deimos::KafkaMessage.
          select('count(*) as num_messages, min(created_at) as earliest, topic').
          group(:topic)
        if messages.none?
          metrics.gauge('pending_db_messages_max_wait', 0)
        end
        messages.each do |record|
          earliest = record.earliest
          # SQLite gives a string here
          earliest = Time.zone.parse(earliest) if earliest.is_a?(String)

          time_diff = Time.zone.now - earliest
          metrics.gauge('pending_db_messages_max_wait', time_diff,
                        tags: ["topic:#{record.topic}"])
        end
      end

      # Shut down the sync producer if we have to. Phobos will automatically
      # create a new one. We should call this if the producer can be in a bad
      # state and e.g. we need to clear the buffer.
      def shutdown_producer
        if self.class.producer.respond_to?(:sync_producer_shutdown) # Phobos 1.8.3
          self.class.producer.sync_producer_shutdown
        end
      end

      # @param batch [Array<Hash>]
      def produce_messages(batch)
        batch_size = batch.size
        begin
          batch.in_groups_of(batch_size, false).each do |group|
            @logger.debug("Publishing #{group.size} messages to #{@current_topic}")
            producer.publish_list(group)
            Deimos.config.metrics&.increment(
              'publish',
              tags: %W(status:success topic:#{@current_topic}),
              by: group.size
            )
            @logger.info("Sent #{group.size} messages to #{@current_topic}")
          end
        rescue Kafka::BufferOverflow, Kafka::MessageSizeTooLarge,
               Kafka::RecordListTooLarge => e
          if batch_size == 1
            shutdown_producer
            raise
          end

          @logger.error("Got error #{e.class.name} when publishing #{batch.size} in groups of #{batch_size}, retrying...")
          if batch_size < 10
            batch_size = 1
          else
            batch_size /= 10
          end
          shutdown_producer
          retry
        end
      end

      # @param batch [Array<Deimos::KafkaMessage>]
      # @return [Array<Deimos::KafkaMessage>]
      def compact_messages(batch)
        return batch unless batch.first&.key.present?

        topic = batch.first.topic
        return batch if config.compact_topics != :all &&
                        !config.compact_topics.include?(topic)

        batch.reverse.uniq!(&:key).reverse!
      end
    end
  end
end
