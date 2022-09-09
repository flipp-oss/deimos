# frozen_string_literal: true

module Deimos
  module Backends
    # Abstract class for all publish backends.
    class Base
      class << self
        # @param producer_class [Class<Deimos::Producer>]
        # @param messages [Array<Deimos::Message>]
        # @return [void]
        def publish(producer_class:, messages:)
          Deimos.config.logger.info(
            message: 'Publishing messages',
            topic: producer_class.topic,
            payloads: messages.map do |message|
              {
                payload: message.payload,
                key: message.key
              }
            end
          )
          execute(producer_class: producer_class, messages: messages)
        end

        # @param producer_class [Class<Deimos::Producer>]
        # @param messages [Array<Deimos::Message>]
        # @return [void]
        def execute(producer_class:, messages:)
          raise NotImplementedError
        end
      end
    end
  end
end
