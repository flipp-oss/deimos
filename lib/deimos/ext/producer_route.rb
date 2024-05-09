module Deimos
  class ProducerRoute < Karafka::Routing::Features::Base
    module Topic
      def producer_class(klass=nil)
        active(false)
        @producer_class ||= klass
      end
    end
  end
end

Deimos::ProducerRoute.activate
