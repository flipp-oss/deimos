# frozen_string_literal: true

require 'phobos/producer'

module Phobos
  module Producer
    # :nodoc:
    class PublicAPI
      # :nodoc:
      def publish(topic, payload, key=nil, partition_key=nil)
        class_producer.publish(topic, payload, key, partition_key)
      end

      # :nodoc:
      def async_publish(topic, payload, key=nil, partition_key=nil)
        class_producer.async_publish(topic, payload, key, partition_key)
      end
    end

    # :nodoc:
    module ClassMethods
      # :nodoc:
      class PublicAPI
        # :nodoc:
        def publish(topic, payload, key=nil, partition_key=nil)
          publish_list([{ topic: topic, payload: payload, key: key,
                          partition_key: partition_key }])
        end

        # :nodoc:
        def async_publish(topic, payload, key=nil, partition_key=nil)
          async_publish_list([{ topic: topic, payload: payload, key: key,
                                partition_key: partition_key }])
        end

      private

        # :nodoc:
        def produce_messages(producer, messages)
          messages.each do |message|
            partition_key = message[:partition_key] || message[:key]
            producer.produce(message[:payload],
                             topic: message[:topic],
                             key: message[:key],
                             partition_key: partition_key)
          end
        end
      end
    end
  end
end
