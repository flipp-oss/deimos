# frozen_string_literal: true

module Deimos
  module Backends
    # Backend which produces to Kafka via an async producer.
    class KafkaAsync < Deimos::PublishBackend
      include Phobos::Producer

      # Shut down the producer cleanly.
      def self.shutdown_producer
        producer.async_producer_shutdown
        producer.kafka_client&.close
      end

      # :nodoc:
      def self.execute(producer_class:, messages:)
        Deimos.instrument(
          'produce',
          producer: producer_class,
          topic: producer_class.topic,
          payloads: messages.map(&:payload)
        ) do
          producer.async_publish_list(messages.map(&:encoded_hash))
          Deimos.config.metrics&.increment(
            'publish',
            tags: %W(status:success topic:#{producer_class.topic}),
            by: messages.size
          )
        end
      end
    end
  end
end
