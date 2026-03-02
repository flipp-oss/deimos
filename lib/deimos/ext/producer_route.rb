# frozen_string_literal: true

module Deimos
  class ProducerRoute < Karafka::Routing::Features::Base
    FIELDS = %i(producer_classes payload_log disabled).freeze

    Config = Struct.new(*FIELDS, keyword_init: true) do
      def producer_class=(val)
        self.producer_classes = [val]
      end

      def producer_class
        self.producer_classes&.first
      end
    end

    module Topic
      (FIELDS + [:producer_class]).each do |field|
        define_method(field) do |*args|
          active(false) if %i(producer_class producer_classes).include?(field) && args.any?
          @deimos_producer_config ||= Config.new
          if args.any?
            @deimos_producer_config.public_send("#{field}=", args[0])
            _deimos_setup_transcoders if schema && namespace
          end
          @deimos_producer_config.send(field)
        end
      end
    end
  end
end

Deimos::ProducerRoute.activate
