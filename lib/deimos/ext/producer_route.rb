module Deimos
  class ProducerRoute < Karafka::Routing::Features::Base
    FIELDS = %i(producer_class payload_log disabled)

    Config = Struct.new(*FIELDS, keyword_init: true)
    module Topic
      FIELDS.each do |field|
        define_method(field) do |*args|
          active(false) if field == :producer_class
          @deimos_producer_config ||= Config.new
          if args.any?
            @deimos_producer_config.public_send("#{field}=", args[0])
            _deimos_setup_transcoders if schema && namespace
          end
          @deimos_producer_config[field]
        end
      end
    end
  end
end

Deimos::ProducerRoute.activate
