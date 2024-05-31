# frozen_string_literal: true

module Deimos
  module Backends
    # Backend which produces to Kafka via an async producer.
    class KafkaAsync < Base
      # :nodoc:
      def self.execute(producer_class:, messages:)
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
