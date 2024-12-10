module Deimos
  module Logging
    class << self

      def log_add(method, msg)
        if Karafka.logger.respond_to?(:tagged)
          Karafka.logger.tagged('Deimos') do |logger|
            logger.send(method, msg.to_json)
          end
        else
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

      def _payloads(messages)

      end

      def messages_log_text(payload_log, messages)
        log_message = {}

        case payload_log
        when :keys
          keys = messages.map do |m|
            m.respond_to?(:payload) ? m.key || m.payload['message_id'] : m[:key] || m[:payload_key] || m[:payload]['message_id']
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
                payload: m.respond_to?(:payload) ? m.payload : m[:payload],
                key: m.respond_to?(:payload) ? m.key : m[:key]
              }
            end
          )
        end

        log_message
      end

    end
  end
end
