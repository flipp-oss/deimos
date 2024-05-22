# frozen_string_literal: true

require 'deimos/consume/batch_consumption'
require 'deimos/consume/message_consumption'

# Class to consume messages coming from a Kafka topic
# Note: According to the docs, instances of your handler will be created
# for every incoming message/batch. This class should be lightweight.
module Deimos
  # Basic consumer class. Inherit from this class and override either consume
  # or consume_batch, depending on the delivery mode of your listener.
  # `consume` -> use `delivery :message` or `delivery :batch`
  # `consume_batch` -> use `delivery :inline_batch`
  class Consumer < Karafka::BaseConsumer
    include Consume::MessageConsumption
    include Consume::BatchConsumption
    include SharedConfig

    def consume
      _with_span do
        if self.topic.batch
          begin
            consume_batch
            _received_batch(messages, {})
          rescue StandardError => e
            _error(e, messages)
          end
        else
          messages.each do |message|
            begin
              consume_message(message)
              _received_message(message)
              mark_as_consumed(message)
            rescue StandardError => e
              _error(e, messages)
            end
          end
        end
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

    def _report_time_delayed(message)
      return if message.payload.nil? || message.payload['timestamp'].blank?

      begin
        time_delayed = Time.now.in_time_zone - message.payload['timestamp'].to_datetime
      rescue ArgumentError
        Deimos.config.logger.info(
          message: "Error parsing timestamp! #{message.payload['timestamp']}"
        )
        return
      end
      Deimos.config.metrics&.histogram('handler', time_delayed, tags: %W(
                                         time:time_delayed
                                         topic:#{topic.name}
                                       ))
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

    # Enable legacy mode - i.e. `consume` method takes parameters
    def self.legacy_mode!
      alias_method(:consume, :consume_message)
      define_method(:consume) { |*args, **kwargs| super(*args, **kwargs)}
      alias_method(:consume_message_batch, :consume_batch)
      define_method(:consume_batch) do
        consume_message_batch(messages, {})
      end
    end

  end
end
