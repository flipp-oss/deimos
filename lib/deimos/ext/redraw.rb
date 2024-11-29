# This is for temporary testing until https://github.com/karafka/karafka/pull/2347 is merged and released.

module Karafka
  module Routing
    class Builder < Array
      alias array_clear clear

      def clear
        @mutex.synchronize do
          @defaults = EMPTY_DEFAULTS
          @draws.clear
          array_clear
        end
      end

      def redraw(&block)
        @mutex.synchronize do
          @draws.clear
          array_clear
        end
        draw(&block)
      end

    end
  end
end

require 'karafka'
require 'karafka/routing/builder'
