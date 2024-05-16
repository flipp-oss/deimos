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
          Deimos.config.logger.info(log_message(producer_class, messages))
          execute(producer_class: producer_class, messages: messages)
        end

        def log_message(producer_class, messages)
          log_message = {
            message: 'Publishing messages',
          }

          case producer_class.karafka_config.payload_log
          when :keys
            log_message.merge!(
              payload_keys: messages.map { |m| m[:key]}
            )
          when :count
            log_message.merge!(
              payloads_count: messages.count
            )
          when :headers
            log_message.merge!(
              payload_headers: messages.map { |m| m[:headers] }
            )
          else
            log_message.merge!(
              payloads: messages.map do |message|
                {
                  payload: message[:payload],
                  key: message[:key]
                }
              end
            )
          end

          log_message
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
