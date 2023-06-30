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
          Deimos.config.logger.info(log_message(messages))
          execute(producer_class: producer_class, messages: messages)
        end

        # @param producer_class [Class<Deimos::Producer>]
        # @param messages [Array<Deimos::Message>]
        # @return [void]
        def execute(producer_class:, messages:)
          raise NotImplementedError
        end

      private

        def log_message(messages)
          log_message = {
            message: 'Publishing messages',
            topic: messages.first&.topic
          }

          case Deimos.config.payload_log
          when :keys
            log_message.merge!(
              payload_keys: messages.map(&:key)
            )
          when :count
            log_message.merge!(
              payloads_count: messages.count
            )
          when :headers
            log_message.merge!(
              payload_headers: messages.map(&:headers)
            )
          else
            log_message.merge!(
              payloads: messages.map do |message|
                {
                  payload: message.payload,
                  key: message.key
                }
              end
            )
          end

          log_message
        end
      end
    end
  end
end
