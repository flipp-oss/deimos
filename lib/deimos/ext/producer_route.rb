module Deimos
  class ProducerRoute < Karafka::Routing::Features::Base
    FIELDS = %i(producer_class payload_log disabled)

    Config = Struct.new(*FIELDS, keyword_init: true)
    module Topic
      FIELDS.each do |field|
        define_method(field) do |val=Karafka::Routing::Default.new(nil)|
          active(false) if field == :producer_class
          @deimos_producer_config ||= Config.new
          unless val.is_a?(Karafka::Routing::Default)
            @deimos_producer_config.public_send("#{field}=", val)
            _deimos_setup_transcoders if schema && namespace
          end
          @deimos_producer_config[field]
        end
      end
    end
  end
end

Deimos::ProducerRoute.activate
