# frozen_string_literal: true

module Deimos
  module Utils
    # Utility class to retry a given block if a a deadlock is encountered.
    # Supports Postgres and MySQL deadlocks and lock wait timeouts.
    class DeadlockRetry
      class << self
        # Maximum number of times to retry the block after encountering a deadlock
        RETRY_COUNT = 2

        # Need to match on error messages to support older Rails versions
        DEADLOCK_MESSAGES = [
          # MySQL
          'Deadlock found when trying to get lock',
          'Lock wait timeout exceeded',

          # Postgres
          'deadlock detected'
        ].freeze

        # Retry the given block when encountering a deadlock. For any other
        # exceptions, they are reraised. This is used to handle cases where
        # the database may be busy but the transaction would succeed if
        # retried later. Note that your block should be idempotent and it will
        # be wrapped in a transaction.
        # Sleeps for a random number of seconds to prevent multiple transactions
        # from retrying at the same time.
        # @param tags [Array] Tags to attach when logging and reporting metrics.
        # @yield Yields to the block that may deadlock.
        def wrap(tags=[])
          count = RETRY_COUNT

          begin
            ::ActiveRecord::Base.transaction do
              yield
            end
          rescue ::ActiveRecord::StatementInvalid => e
            # Reraise if not a known deadlock
            raise if DEADLOCK_MESSAGES.none? { |m| e.message.include?(m) }

            # Reraise if all retries exhausted
            raise if count <= 0

            Deimos.config.logger.warn(
              message: 'Deadlock encountered when trying to execute query. '\
                "Retrying. #{count} attempt(s) remaining",
              tags: tags
            )

            Deimos.config.metrics&.increment(
              'deadlock',
              tags: tags
            )

            count -= 1

            # Sleep for a random amount so that if there are multiple
            # transactions deadlocking, they don't all retry at the same time
            sleep(Random.rand(5.0) + 0.5)

            retry
          end
        end
      end
    end
  end
end
