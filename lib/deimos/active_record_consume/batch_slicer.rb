# frozen_string_literal: true

module Deimos
  module ActiveRecordConsume
    # Helper class for breaking down batches into independent groups for
    # processing
    class BatchSlicer
      # Split the batch into a series of independent slices. Each slice contains
      # messages that can be processed in any order (i.e. they have distinct
      # keys). Messages with the same key will be separated into different
      # slices that maintain the correct order.
      # E.g. Given messages A1, A2, B1, C1, C2, C3, they will be sliced as:
      # [[A1, B1, C1], [A2, C2], [C3]]
      # @param messages [Array<Message>]
      # @return [Array<Array<Message>>]
      def self.slice(messages)
        ops = messages.group_by(&:key)

        # Find maximum depth
        depth = ops.values.map(&:length).max || 0

        # Generate slices for each depth
        depth.times.map do |i|
          ops.values.map { |arr| arr.dig(i) }.compact
        end
      end
    end
  end
end
