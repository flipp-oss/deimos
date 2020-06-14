# frozen_string_literal: true

module ConsumerTest
  # Mock consumer
  class MyBatchConsumer < Deimos::Consumer
    # :no-doc:
    def consume_batch
    end
  end
end
