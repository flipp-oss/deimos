# frozen_string_literal: true

require 'mutex_m'

# :nodoc:
module Deimos
  module Utils
    # Class that manages reporting lag.
    class LagReporter
      extend Mutex_m

      # Class that has a list of topics
      class ConsumerGroup
        # @return [Hash<String, Topic>]
        attr_accessor :topics
        # @return [String]
        attr_accessor :id

        # @param id [String]
        def initialize(id)
          self.id = id
          self.topics = {}
        end

        # @param topic [String]
        # @param partition [Integer]
        def report_lag(topic, partition)
          self.topics[topic.to_s] ||= Topic.new(topic, self)
          self.topics[topic.to_s].report_lag(partition)
        end

        # @param topic [String]
        # @param partition [Integer]
        # @param lag [Integer]
        def assign_lag(topic, partition, lag)
          self.topics[topic.to_s] ||= Topic.new(topic, self)
          self.topics[topic.to_s].assign_lag(partition, lag)
        end

        # Figure out the current lag by asking Kafka based on the current offset.
        # @param topic [String]
        # @param partition [Integer]
        # @param offset [Integer]
        def compute_lag(topic, partition, offset)
          self.topics[topic.to_s] ||= Topic.new(topic, self)
          self.topics[topic.to_s].compute_lag(partition, offset)
        end
      end

      # Topic which has a hash of partition => last known offset lag
      class Topic
        # @return [String]
        attr_accessor :topic_name
        # @return [Hash<Integer, Integer>]
        attr_accessor :partition_offset_lags
        # @return [ConsumerGroup]
        attr_accessor :consumer_group

        # @param topic_name [String]
        # @param group [ConsumerGroup]
        def initialize(topic_name, group)
          self.topic_name = topic_name
          self.consumer_group = group
          self.partition_offset_lags = {}
        end

        # @param partition [Integer]
        # @param lag [Integer]
        def assign_lag(partition, lag)
          self.partition_offset_lags[partition.to_i] = lag
        end

        # @param partition [Integer]
        # @param offset [Integer]
        def compute_lag(partition, offset)
          return if self.partition_offset_lags[partition.to_i]

          begin
            client = Phobos.create_kafka_client
            last_offset = client.last_offset_for(self.topic_name, partition)
            assign_lag(partition, [last_offset - offset, 0].max)
          rescue StandardError # don't do anything, just wait
            Deimos.config.logger.
              debug("Error computing lag for #{self.topic_name}, will retry")
          end
        end

        # @param partition [Integer]
        def report_lag(partition)
          lag = self.partition_offset_lags[partition.to_i]
          return unless lag

          group = self.consumer_group.id
          Deimos.config.logger.
            debug("Sending lag: #{group}/#{partition}: #{lag}")
          Deimos.config.metrics&.gauge('consumer_lag', lag, tags: %W(
            consumer_group:#{group}
            partition:#{partition}
            topic:#{self.topic_name}
          ))
        end
      end

      @groups = {}

      class << self
        # Reset all group information.
        def reset
          @groups = {}
        end

        # @param payload [Hash]
        def message_processed(payload)
          lag = payload[:offset_lag]
          topic = payload[:topic]
          group = payload[:group_id]
          partition = payload[:partition]

          synchronize do
            @groups[group.to_s] ||= ConsumerGroup.new(group)
            @groups[group.to_s].assign_lag(topic, partition, lag)
          end
        end

        # @param payload [Hash]
        def offset_seek(payload)
          offset = payload[:offset]
          topic = payload[:topic]
          group = payload[:group_id]
          partition = payload[:partition]

          synchronize do
            @groups[group.to_s] ||= ConsumerGroup.new(group)
            @groups[group.to_s].compute_lag(topic, partition, offset)
          end
        end

        # @param payload [Hash]
        def heartbeat(payload)
          group = payload[:group_id]
          synchronize do
            @groups[group.to_s] ||= ConsumerGroup.new(group)
            consumer_group = @groups[group.to_s]
            payload[:topic_partitions].each do |topic, partitions|
              partitions.each do |partition|
                consumer_group.report_lag(topic, partition)
              end
            end
          end
        end
      end
    end
  end

  ActiveSupport::Notifications.subscribe('start_process_message.consumer.kafka') do |*args|
    next unless Deimos.config.report_lag

    event = ActiveSupport::Notifications::Event.new(*args)
    Deimos::Utils::LagReporter.message_processed(event.payload)
  end

  ActiveSupport::Notifications.subscribe('start_process_batch.consumer.kafka') do |*args|
    next unless Deimos.config.report_lag

    event = ActiveSupport::Notifications::Event.new(*args)
    Deimos::Utils::LagReporter.message_processed(event.payload)
  end

  ActiveSupport::Notifications.subscribe('seek.consumer.kafka') do |*args|
    next unless Deimos.config.report_lag

    event = ActiveSupport::Notifications::Event.new(*args)
    Deimos::Utils::LagReporter.offset_seek(event.payload)
  end

  ActiveSupport::Notifications.subscribe('heartbeat.consumer.kafka') do |*args|
    next unless Deimos.config.report_lag

    event = ActiveSupport::Notifications::Event.new(*args)
    Deimos::Utils::LagReporter.heartbeat(event.payload)
  end
end
