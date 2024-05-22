# frozen_string_literal: true

require 'deimos/kafka_message'

module Deimos
  module Backends
    # Backend which saves messages to the database instead of immediately
    # sending them.
    class Db < Base
      class << self
        # :nodoc:
        def execute(producer_class:, messages:)
          records = messages.map do |m|
            Deimos::ProducerMiddleware.call(m)
            message = Deimos::KafkaMessage.new(
              message: m[:payload] ? m[:payload].to_s.b : nil,
              topic: m[:topic],
              partition_key: partition_key_for(m)
            )
            message.key = m[:key].to_s.b if m[:key]
            message
          end
          Deimos::KafkaMessage.import(records)
          Deimos.config.metrics&.increment(
            'db_producer.insert',
            tags: %W(topic:#{producer_class.topic}),
            by: records.size
          )
        end

        # @param message [Deimos::Message]
        # @return [String] the partition key to use for this message
        def partition_key_for(message)
          if message[:partition_key].present?
            message[:partition_key]
          elsif message[:key].present?
            message[:key].to_s.b
          else
            nil
          end
        end
      end
    end
  end
end
