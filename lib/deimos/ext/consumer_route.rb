module Deimos
  class ConsumerRoute < Karafka::Routing::Features::Base
    module Topic
      def batch(bool=nil)
        return @batch if bool.nil?
        @batch = bool
      end
    end
  end
end

Deimos::ConsumerRoute.activate
