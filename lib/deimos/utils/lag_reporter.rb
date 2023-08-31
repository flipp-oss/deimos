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
        # @return [void]
        def report_lag(topic, partition)
          self.topics[topic.to_s] ||= Topic.new(topic, self)
          self.topics[topic.to_s].report_lag(partition)
        end

        # @param topic [String]
        # @param partition [Integer]
        # @param offset [Integer]
        # @return [void]
        def assign_current_offset(topic, partition, offset)
          self.topics[topic.to_s] ||= Topic.new(topic, self)
          self.topics[topic.to_s].assign_current_offset(partition, offset)
        end
      end

      # Topic which has a hash of partition => last known current offsets
      class Topic
        # @return [String]
        attr_accessor :topic_name
        # @return [Hash<Integer, Integer>]
        attr_accessor :partition_current_offsets
        # @return [Deimos::Utils::LagReporter::ConsumerGroup]
        attr_accessor :consumer_group

        # @param topic_name [String]
        # @param group [Deimos::Utils::LagReporter::ConsumerGroup]
        def initialize(topic_name, group)
          self.topic_name = topic_name
          self.consumer_group = group
          self.partition_current_offsets = {}
        end

        # @param partition [Integer]
        # @param offset [Integer]
        # @return [void]
        def assign_current_offset(partition, offset)
          self.partition_current_offsets[partition.to_i] = offset
        end

        # @param partition [Integer]
        # @param offset [Integer]
        # @return [Integer]
        def compute_lag(partition, offset)
          begin
            client = Phobos.create_kafka_client
            last_offset = client.last_offset_for(self.topic_name, partition)
            lag = last_offset - offset
          rescue StandardError # don't do anything, just wait
            Deimos.config.logger.
              debug("Error computing lag for #{self.topic_name}, will retry")
          end
          lag || 0
        end

        # @param partition [Integer]
        # @return [void]
        def report_lag(partition)
          current_offset = self.partition_current_offsets[partition.to_i]
          return unless current_offset

          lag = compute_lag(partition, current_offset)
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
        # @return [void]
        def reset
          @groups = {}
        end

        # offset_lag = event.payload.fetch(:offset_lag)
        # group_id = event.payload.fetch(:group_id)
        # topic = event.payload.fetch(:topic)
        # partition = event.payload.fetch(:partition)
        # @param payload [Hash]
        # @return [void]
        def message_processed(payload)
          offset = payload[:offset] || payload[:last_offset]
          topic = payload[:topic]
          group = payload[:group_id]
          partition = payload[:partition]

          synchronize do
            @groups[group.to_s] ||= ConsumerGroup.new(group)
            @groups[group.to_s].assign_current_offset(topic, partition, offset)
          end
        end

        # @param payload [Hash]
        # @return [void]
        def offset_seek(payload)
          offset = payload[:offset]
          topic = payload[:topic]
          group = payload[:group_id]
          partition = payload[:partition]

          synchronize do
            @groups[group.to_s] ||= ConsumerGroup.new(group)
            @groups[group.to_s].assign_current_offset(topic, partition, offset)
          end
        end

        # @param payload [Hash]
        # @return [void]
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
    next unless Deimos.config.consumers.report_lag

    event = ActiveSupport::Notifications::Event.new(*args)
    Deimos::Utils::LagReporter.message_processed(event.payload)
  end

  ActiveSupport::Notifications.subscribe('start_process_batch.consumer.kafka') do |*args|
    next unless Deimos.config.consumers.report_lag

    event = ActiveSupport::Notifications::Event.new(*args)
    Deimos::Utils::LagReporter.message_processed(event.payload)
  end

  ActiveSupport::Notifications.subscribe('seek.consumer.kafka') do |*args|
    next unless Deimos.config.consumers.report_lag

    event = ActiveSupport::Notifications::Event.new(*args)
    Deimos::Utils::LagReporter.offset_seek(event.payload)
  end

  ActiveSupport::Notifications.subscribe('heartbeat.consumer.kafka') do |*args|
    next unless Deimos.config.consumers.report_lag

    event = ActiveSupport::Notifications::Event.new(*args)
    Deimos::Utils::LagReporter.heartbeat(event.payload)
  end
end
