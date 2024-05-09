module Deimos
  class ProducerRoute < Karafka::Routing::Features::Base
    module Topic
      def producer(klass=nil)
        active(false)
        @producer ||= klass
      end
    end
  end
end

Deimos::ProducerRoute.activate
