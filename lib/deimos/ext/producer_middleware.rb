module Deimos
  module ProducerMiddleware
    class << self

      attr_accessor :producer_configs

      def call(message)
        config = producer_configs[message[:topic]]


      end
    end
  end
end
