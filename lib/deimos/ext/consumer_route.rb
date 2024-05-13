module Deimos
  class ConsumerRoute < Karafka::Routing::Features::Base
    module Topic
      def batch(bool=nil)
        return @_deimos_config[:batch] if bool.nil?
        @_deimos_config[:batch] = bool
      end
    end
  end
end

Deimos::ConsumerRoute.activate
