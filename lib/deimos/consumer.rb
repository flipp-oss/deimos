# frozen_string_literal: true

require 'deimos/consume/batch_consumption'
require 'deimos/consume/message_consumption'

# Class to consume messages coming from a Kafka topic
# Note: According to the docs, instances of your handler will be created
# for every incoming message/batch. This class should be lightweight.
module Deimos
  # Basic consumer class. Inherit from this class and override either consume_message
  # or consume_batch, depending on the `:batch` config setting.
  class Consumer < Karafka::BaseConsumer
    include Consume::MessageConsumption
    include Consume::BatchConsumption
    include SharedConfig

    def consume
      if self.topic.each_message
        _consume_messages
      else
        _consume_batch
      end
    end

  private

    def _with_span
      @span = Deimos.config.tracer&.start(
        'deimos-consumer',
        resource: self.class.name.gsub('::', '-')
      )
      yield
    ensure
      Deimos.config.tracer&.finish(@span)
    end

    # Overrideable method to determine if a given error should be considered
    # "fatal" and always be reraised.
    # @param _error [Exception]
    # @param _messages [Array<Karafka::Message>]
    # @return [Boolean]
    def fatal_error?(_error, _messages)
      false
    end

    # @param exception [Exception]
    # @param messages [Array<Karafka::Message>]
    def _error(exception, messages)
      Deimos.config.tracer&.set_error(@span, exception)

      raise if self.topic.reraise_errors ||
               Deimos.config.consumers.fatal_error&.call(exception, messages) ||
               fatal_error?(exception, messages)
    end

  end
end
