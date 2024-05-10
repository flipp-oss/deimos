module Deimos
  module LoggerListener
    def on_consumer_consume(event)
      puts event
    end
  end
end
