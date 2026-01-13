# frozen_string_literal: true

module Deimos
  module Backends
    # Backend which produces to Kafka via an async producer.
    class KafkaAsync < Base

      # :nodoc:
      def self.execute(producer_class:, messages:)
        Deimos.producer_for(producer_class.topic).produce_many_async(messages)
      end
    end
  end
end
