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
  class Handler
    include Consume::MessageConsumption
    include Consume::BatchConsumption

    private

    # Make sure this makes sense here and not somewhere else. E.g consumer
    def _with_span
      @span = Deimos.config.tracer&.start(
        'deimos-consumer',
        resource: self.class.name.gsub('::', '-')
      )
      yield
    ensure
      Deimos.config.tracer&.finish(@span)
    end

    def _report_time_delayed(payload, metadata)
      return if payload.nil? || payload['timestamp'].blank?

      begin
        time_delayed = Time.now.in_time_zone - payload['timestamp'].to_datetime
      rescue ArgumentError
        Deimos.config.logger.info(
          message: "Error parsing timestamp! #{payload['timestamp']}"
        )
        return
      end
      Deimos.config.metrics&.histogram('handler', time_delayed, tags: %W(
                                         time:time_delayed
                                         topic:#{metadata[:topic]}
                                       ))
    end

    # Overrideable method to determine if a given error should be considered
    # "fatal" and always be reraised.
    # @param _error [Exception]
    # @param _payload [Hash]
    # @param _metadata [Hash]
    # @return [Boolean]
    def fatal_error?(_error, _payload, _metadata)
      false
    end

    # @param exception [Exception]
    # @param payload [Hash]
    # @param metadata [Hash]
    def _error(exception, payload, metadata)
      Deimos.config.tracer&.set_error(@span, exception)

      raise if Deimos.config.consumers.reraise_errors ||
               Deimos.config.consumers.fatal_error&.call(exception, payload, metadata) ||
               fatal_error?(exception, payload, metadata)
    end
  end
end
