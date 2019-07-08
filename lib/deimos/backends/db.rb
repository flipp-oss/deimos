# frozen_string_literal: true

require 'deimos/kafka_message'

module Deimos
  module Backends
    # Backend which saves messages to the database instead of immediately
    # sending them.
    class Db < Deimos::PublishBackend

      class << self
        # :nodoc:
        def execute(producer_class:, messages:)
          records = messages.map do |m|
            message = Deimos::KafkaMessage.new(
              message: m.encoded_payload.to_s.b,
              topic: m.topic,
              partition_key: m.partition_key || m.key
            )
            unless producer_class.config[:no_keys]
              message.key = m.encoded_key.to_s.b
            end
            message
          end
          Deimos::KafkaMessage.import(records)
        end
      end
    end
  end
end
