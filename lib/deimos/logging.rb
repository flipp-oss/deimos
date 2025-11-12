# frozen_string_literal: true

module Deimos
  module Logging
    class << self

      def log_add(method, msg)
        if Karafka.logger.respond_to?(:tagged)
          Karafka.logger.tagged('Deimos') do |logger|
            logger.send(method, msg)
          end
        else
          Karafka.logger.send(method, msg)
        end
      end

      def log_info(*args)
        log_add(:info, *args)
      end

      def log_debug(*args)
        log_add(:debug, *args)
      end

      def log_error(*args)
        log_add(:error, *args)
      end

      def log_warn(*args)
        log_add(:warn, *args)
      end

      def metadata_log_text(metadata)
        metadata.to_h.slice(:timestamp, :offset, :first_offset, :last_offset, :partition, :topic, :size)
      end

      def _payloads(messages)
      end

      def payload(m)
        return nil if m.nil?

        if m.respond_to?(:payload)
          m.payload
        elsif m[:label]
          m.dig(:label, :original_payload)
        else
          m[:payload]
        end
      end

      def key(m)
        return nil if m.nil?

        if m.respond_to?(:payload) && m.payload
          m.key || m.payload['message_id']
        elsif m.respond_to?(:[])
          if m[:label]
            m.dig(:label, :original_key)
          elsif m[:payload].is_a?(String)
            m[:key] || m[:payload_key]
          else
            payload = m[:payload]&.with_indifferent_access
            m[:key] || m[:payload_key] || payload[:payload_key] || payload[:message_id]
          end
        end
      end

      def messages_log_text(payload_log, messages)
        log_message = {}

        case payload_log
        when :keys
          keys = messages.map do |m|
            key(m)
          end
          log_message.merge!(
            payload_keys: keys
          )
        when :count
          log_message.merge!(
            payloads_count: messages.count
          )
        when :headers
          log_message.merge!(
            payload_headers: messages.map { |m| m.respond_to?(:headers) ? m.headers : m[:headers] }
          )
        else
          log_message.merge!(
            payloads: messages.map do |m|
              {
                payload: payload(m),
                key: key(m)
              }
            end
          )
        end

        log_message
      end

    end
  end
end
