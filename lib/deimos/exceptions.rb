# frozen_string_literal: true

module Deimos
  class MissingImplementationError < StandardError; end

  # Raised when a batch database operation failed and the messages were retried one at a time.
  # Every message that could be saved on its own has been saved; this carries the ones that could
  # not, so that the offending keys show up in logging and error reporting.
  class BatchFallbackError < StandardError
    # @return [Array<Array(Deimos::Message, StandardError)>] each message that failed on its own,
    #   paired with the error it raised.
    attr_reader :failures

    # @param failures [Array<Array(Deimos::Message, StandardError)>]
    def initialize(failures)
      @failures = failures
      details = failures.map { |message, error| "#{message.key.inspect} (#{error.message})" }
      super("#{failures.size} message(s) could not be saved individually after the batch " \
            "failed. Failed keys: #{details.join(', ')}")
    end
  end
end
