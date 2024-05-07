module Deimos
  class ProducerMiddleware

    class << self
      attr_accessor :topic_config
    end

    def call(message)
      schema = self.to
    end
  end
end
