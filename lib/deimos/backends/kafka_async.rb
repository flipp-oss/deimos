# frozen_string_literal: true

module Deimos
  module Backends
    # Backend which produces to Kafka via an async producer.
    class KafkaAsync < Base
      # :nodoc:
      def self.execute(producer_class:, messages:)
        Deimos.instrument(
          'produce',
          producer: producer_class,
          topic: messages.first[:topic],
          payloads: messages.map { |m| m[:payload]}
        ) do
          Karafka.producer.produce_many_async(messages)
          Deimos.config.metrics&.increment(
            'publish',
            tags: %W(status:success topic:#{messages.first[:topic]}),
            by: messages.size
          )
        end
      end
    end
  end
end
