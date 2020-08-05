# frozen_string_literal: true

require 'active_support/notifications'
require 'active_support/concern'

# :nodoc:
module Deimos
  # Copied from Phobos instrumentation.
  module Instrumentation
    extend ActiveSupport::Concern
    NAMESPACE = 'Deimos'

    # :nodoc:
    module ClassMethods
      # :nodoc:
      def subscribe(event)
        ActiveSupport::Notifications.subscribe("#{NAMESPACE}.#{event}") do |*args|
          yield(ActiveSupport::Notifications::Event.new(*args)) if block_given?
        end
      end

      # :nodoc:
      def unsubscribe(subscriber)
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      # :nodoc:
      def instrument(event, extra={})
        ActiveSupport::Notifications.instrument("#{NAMESPACE}.#{event}", extra) do |extra2|
          yield(extra2) if block_given?
        end
      end
    end
  end

  include Instrumentation

  # This module listens to events published by RubyKafka.
  module KafkaListener
    # Listens for any exceptions that happen during publishing and re-publishes
    # as a Deimos event.
    # @param event [ActiveSupport::Notification]
    def self.send_produce_error(event)
      exception = event.payload[:exception_object]
      return if !exception || !exception.respond_to?(:failed_messages)

      messages = exception.failed_messages
      messages.group_by(&:topic).each do |topic, batch|
        producer = Deimos::Producer.descendants.find { |c| c.topic == topic }
        next if batch.empty? || !producer

        decoder = Deimos.schema_backend(schema: producer.config[:schema],
                                        namespace: producer.config[:namespace])
        payloads = batch.map { |m| decoder.decode(m.value) }

        Deimos.config.metrics&.increment(
          'publish_error',
          tags: %W(topic:#{topic}),
          by: payloads.size
        )
        Deimos.instrument(
          'produce_error',
          producer: producer,
          topic: topic,
          exception_object: exception,
          payloads: payloads
        )
      end
    end
  end

  ActiveSupport::Notifications.subscribe('deliver_messages.producer.kafka') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    KafkaListener.send_produce_error(event)
  end
end
