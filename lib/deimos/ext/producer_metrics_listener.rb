# frozen_string_literal: true

module Deimos
  class ProducerMetricsListener
      %i(
        produced_sync
        produced_async
      ).each do |event_scope|
        define_method(:"on_message_#{event_scope}") do |event|
          Deimos.config.metrics&.increment(
            'publish',
            tags: %W(status:success topic:#{event[:message][:topic]})
          )
        end

        define_method(:"on_messages_#{event_scope}") do |event|
          Deimos.config.metrics&.increment(
            'publish',
            tags: %W(status:success topic:#{event[:messages].first[:topic]}),
            by: event[:messages].size
          )
        end
      end
  end
end
