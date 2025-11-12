# frozen_string_literal: true

module Deimos
  module Backends
    # Abstract class for all publish backends.
    class Base
      class << self
        # @param producer_class [Class<Deimos::Producer>]
        # @param messages [Array<Hash>]
        # @return [void]
        def publish(producer_class:, messages:)
          topic = producer_class.topic
          execute(producer_class: producer_class, messages: messages)
          message = ::Deimos::Logging.messages_log_text(producer_class.karafka_config.payload_log, messages)
          Deimos::Logging.log_info({ message: "Publishing Messages for #{topic}:" }.merge(message))
        end

        # @param producer_class [Class<Deimos::Producer>]
        # @param messages [Array<Deimos::Message>]
        # @return [void]
        def execute(producer_class:, messages:)
          raise MissingImplementationError
        end

      end
    end
  end
end
