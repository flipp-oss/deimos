module Deimos
  class ProducerRoute < Karafka::Routing::Features::Base
    Config = Struct.new(
      :producer_class,
      :payload_log,
      :disabled,
      keyword_init: true
    )
    module Topic
      def producer_config(klass: Undefined, payload_log: Undefined)
        active(false)
        @producer_config ||= Config.new(payload_log: :full)

        return @producer_config if [klass, payload_log].uniq == [Undefined]

        @producer_config.producer_class = klass unless klass == Undefined
        @producer_config.payload_log = payload_log unless payload_log == Undefined
      end
    end
  end
end

Deimos::ProducerRoute.activate
