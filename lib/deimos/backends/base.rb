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
          message = ::Deimos::Logging.messages_log_text(producer_class.karafka_config.payload_log, messages)
          Deimos::Logging.log_info({message: 'Publishing Messages:'}.merge(message))
          execute(producer_class: producer_class, messages: messages)
        end

        # @param producer_class [Class<Deimos::Producer>]
        # @param messages [Array<Deimos::Message>]
        # @return [void]
        def execute(producer_class:, messages:)
          raise MissingImplementationError
        end

      private

      end
    end
  end
end
