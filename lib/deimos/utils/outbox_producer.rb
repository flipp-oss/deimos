# frozen_string_literal: true

module Deimos
  module Utils
    # Class which continually polls the kafka_messages table
    # in the database and sends Kafka messages.
    class OutboxProducer
      attr_accessor :id, :current_topic

      # @return [Integer]
      BATCH_SIZE = 1000
      # @return [Integer]
      DELETE_BATCH_SIZE = 10
      # @return [Integer]
      MAX_DELETE_ATTEMPTS = 3
      # @return [Array<Symbol>]
      FATAL_CODES = %i(invalid_msg_size msg_size_too_large)

      # @param logger [Logger]
      def initialize(logger=Logger.new(STDOUT))
        @id = SecureRandom.uuid
        @logger = logger
        @logger.push_tags("OutboxProducer #{@id}") if @logger.respond_to?(:push_tags)
      end

      # @return [FigTree]
      def config
        Deimos.config.outbox
      end

      # Start the poll.
      # @return [void]
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
      # @return [void]
      def stop
        @logger.info('Received signal to stop')
        @signal_to_stop = true
      end

      # Complete one loop of processing all messages in the DB.
      # @return [void]
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
      # @return [String, nil] the topic that was locked, or nil if none were.
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
      # @return [void]
      def process_topic_batch
        messages = retrieve_messages
        return false if messages.empty?

        batch_size = messages.size
        compacted_messages = compact_messages(messages)
        log_messages(compacted_messages)
        Karafka.monitor.instrument('deimos.outbox.produce', topic: @current_topic, messages: compacted_messages) do
          begin
            produce_messages(compacted_messages.map(&:karafka_message))
          rescue WaterDrop::Errors::ProduceManyError => e
            if FATAL_CODES.include?(e.cause.try(:code))
              @logger.error('Message batch too large, deleting...')
              delete_messages(messages)
              raise e
            end
          end
        end
        delete_messages(messages)
        Deimos.config.metrics&.increment(
          'outbox.process',
          tags: %W(topic:#{@current_topic}),
          by: messages.size
        )
        return false if batch_size < BATCH_SIZE

        KafkaTopicInfo.heartbeat(@current_topic, @id) # keep alive
        send_pending_metrics
        true
      end

      # @param messages [Array<Deimos::KafkaMessage>]
      # @return [void]
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
      # @return [void]
      def log_messages(messages)
        return if config.log_topics != :all && !config.log_topics.include?(@current_topic)

        @logger.debug do
          decoded_messages = Deimos::KafkaMessage.decoded(messages)
          "DB producer: Topic #{@current_topic} Producing messages: #{decoded_messages}}"
        end
      end

      # Send metrics related to pending messages.
      # @return [void]
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

      # Produce messages in batches, reducing the size 1/10 if the batch is too
      # large. Does not retry batches of messages that have already been sent.
      # @param batch [Array<Hash>]
      # @return [void]
      def produce_messages(batch)
        batch_size = batch.size
        current_index = 0
        begin
          batch[current_index..-1].in_groups_of(batch_size, false).each do |group|
            @logger.debug("Publishing #{group.size} messages to #{@current_topic}")
            Karafka.producer.produce_many_sync(group)
            Deimos.config.metrics&.increment(
              'publish',
              tags: %W(status:success topic:#{@current_topic}),
              by: group.size
            )
            current_index += group.size
            @logger.info("Sent #{group.size} messages to #{@current_topic}")
          end
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
