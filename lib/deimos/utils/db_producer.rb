# frozen_string_literal: true

module Deimos
  module Utils
    # Class which continually polls the kafka_messages table
    # in the database and sends Kafka messages.
    class DbProducer
      include Phobos::Producer
      attr_accessor :id, :current_topic

      BATCH_SIZE = 1000
      DELETE_BATCH_SIZE = 10
      MAX_DELETE_ATTEMPTS = 3

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
        KafkaTopicInfo.ping_empty_topics(topics)
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
            delete_messages(messages)
            @logger.error('Message batch too large, deleting...')
            @logger.error(Deimos::KafkaMessage.decoded(messages))
            raise
          end
        end
        delete_messages(messages)
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

      # @param messages [Array<Deimos::KafkaMessage>]
      def delete_messages(messages)
        attempts = 1
        begin
          messages.in_groups_of(DELETE_BATCH_SIZE, false).each do |batch|
            Deimos::KafkaMessage.where(topic: batch.first.topic,
                                       id: batch.map(&:id)).
              delete_all
          end
        rescue StandardError => e
          if (e.message =~ /Lock wait/i || e.message =~ /Lost connection/i) &&
             attempts <= MAX_DELETE_ATTEMPTS
            attempts += 1
            ActiveRecord::Base.connection.verify!
            sleep(1)
            retry
          end
          raise
        end
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

        topics = KafkaTopicInfo.select(%w(topic last_processed_at))
        messages = Deimos::KafkaMessage.
          select('count(*) as num_messages, min(created_at) as earliest, topic').
          group(:topic).
          index_by(&:topic)
        topics.each do |record|
          message_record = messages[record.topic]
          # We want to record the last time we saw any activity, meaning either
          # the oldest message, or the last time we processed, whichever comes
          # last.
          if message_record
            record_earliest = message_record.earliest
            # SQLite gives a string here
            if record_earliest.is_a?(String)
              record_earliest = Time.zone.parse(record_earliest)
            end

            earliest = [record.last_processed_at, record_earliest].max
            time_diff = Time.zone.now - earliest
            metrics.gauge('pending_db_messages_max_wait', time_diff,
                          tags: ["topic:#{record.topic}"])
          else
            # no messages waiting
            metrics.gauge('pending_db_messages_max_wait', 0,
                          tags: ["topic:#{record.topic}"])
          end
          metrics.gauge('pending_db_messages_count', message_record&.num_messages || 0,
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

      # Produce messages in batches, reducing the size 1/10 if the batch is too
      # large. Does not retry batches of messages that have already been sent.
      # @param batch [Array<Hash>]
      def produce_messages(batch)
        batch_size = batch.size
        current_index = 0
        begin
          batch[current_index..-1].in_groups_of(batch_size, false).each do |group|
            @logger.debug("Publishing #{group.size} messages to #{@current_topic}")
            producer.publish_list(group)
            Deimos.config.metrics&.increment(
              'publish',
              tags: %W(status:success topic:#{@current_topic}),
              by: group.size
            )
            current_index += group.size
            @logger.info("Sent #{group.size} messages to #{@current_topic}")
          end
        rescue Kafka::BufferOverflow, Kafka::MessageSizeTooLarge,
               Kafka::RecordListTooLarge => e
          if batch_size == 1
            shutdown_producer
            raise
          end

          @logger.error("Got error #{e.class.name} when publishing #{batch.size} in groups of #{batch_size}, retrying...")
          batch_size = if batch_size < 10
                         1
                       else
                         (batch_size / 10).to_i
                       end
          shutdown_producer
          retry
        end
      end

      # @param batch [Array<Deimos::KafkaMessage>]
      # @return [Array<Deimos::KafkaMessage>]
      def compact_messages(batch)
        return batch if batch.first&.key.blank?

        topic = batch.first.topic
        return batch if config.compact_topics != :all &&
                        !config.compact_topics.include?(topic)

        batch.reverse.uniq(&:key).reverse!
      end
    end
  end
end
