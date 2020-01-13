# frozen_string_literal: true

module Deimos
  module Backends
    # Backend which saves messages to an in-memory hash.
    class Test < Deimos::PublishBackend
      class << self
        # @return [Array<Hash>]
        def sent_messages
          @sent_messages ||= []
        end
      end

      # @override
      def self.execute(producer_class:, messages:)
        self.sent_messages.concat(messages.map(&:to_h))
      end
    end
  end
end
