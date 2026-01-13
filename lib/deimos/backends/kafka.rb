# frozen_string_literal: true

module Deimos
  module Backends
    # Default backend to produce to Kafka.
    class Kafka < Base
      # :nodoc:
      def self.execute(producer_class:, messages:)
        Deimos.producer_for(producer_class.topic).produce_many_sync(messages)
      end
    end
  end
end
