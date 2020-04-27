# frozen_string_literal: true
module Deimos
  # @deprecated Use Deimos::Consumer with `delivery: inline_batch` configured instead
  class BatchConsumer < Consumer
  end
end
