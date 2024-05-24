module Deimos
  module Logging
    class << self

      def log_add(method, msg)
        Karafka.logger.tagged('Deimos') do |logger|
          logger.send(method, msg.to_json)
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

      def messages_log_text(payload_log, messages)
        log_message = {}

        case payload_log
        when :keys
          log_message.merge!(
            payload_keys: messages.map do |m|
              m[:key] || (m[:payload].is_a?(Hash) ? m[:payload]['message_id'] : nil)
            end
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

    end
  end
end
