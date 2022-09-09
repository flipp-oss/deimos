# frozen_string_literal: true

require 'phobos/cli/start'

#@!visibility private
module Phobos
  # :nodoc:
  module CLI
    # :nodoc:
    class Start
      # :nodoc:
      def validate_listeners!
        Phobos.config.listeners.each do |listener|
          handler = listener.handler
          begin
            handler.constantize
          rescue NameError
            error_exit("Handler '#{handler}' not defined")
          end

          delivery = listener.delivery
          if delivery.nil?
            Phobos::CLI.logger.warn do
              Hash(message: "Delivery option should be specified, defaulting to 'batch'"\
               ' - specify this option to silence this message')
            end
          elsif !Listener::DELIVERY_OPTS.include?(delivery)
            error_exit("Invalid delivery option '#{delivery}'. Please specify one of: "\
              "#{Listener::DELIVERY_OPTS.join(', ')}")
          end
        end
      end
    end
  end
end
