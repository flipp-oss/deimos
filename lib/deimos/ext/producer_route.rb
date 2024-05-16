module Deimos
  class ProducerRoute < Karafka::Routing::Features::Base
    FIELDS = %i(producer_class payload_log)

    Config = Struct.new(*FIELDS, keyword_init: true)
    module Topic
      FIELDS.each do |field|
        define_method(field) do |val=Karafka::Routing::Features::Undefined|
          active(false)
          @deimos_producer_config ||= Config.new
          unless val == Karafka::Routing::Features::Undefined
            @deimos_producer_config.public_send("#{field}=", val)
          end
          @deimos_producer_config[field]
        end
      end
    end
  end
end

Deimos::ProducerRoute.activate
