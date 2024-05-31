# frozen_string_literal: true

module Deimos
  module Backends
    # Default backend to produce to Kafka.
    class Kafka < Base
      # :nodoc:
      def self.execute(producer_class:, messages:)
        Karafka.producer.produce_many_sync(messages)
        Deimos.config.metrics&.increment(
          'publish',
          tags: %W(status:success topic:#{messages.first[:topic]}),
          by: messages.size
        )
      end
    end
  end
end
