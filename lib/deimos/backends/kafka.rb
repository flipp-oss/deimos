# frozen_string_literal: true

module Deimos
  module Backends
    # Default backend to produce to Kafka.
    class Kafka < Deimos::PublishBackend
      include Phobos::Producer

      # Shut down the producer if necessary.
      def self.shutdown_producer
        producer.sync_producer_shutdown if producer.respond_to?(:sync_producer_shutdown)
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
          producer.publish_list(messages.map(&:encoded_hash))
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
