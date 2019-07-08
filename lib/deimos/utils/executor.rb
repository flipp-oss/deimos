# frozen_string_literal: true

# rubocop:disable Lint/RescueException
module Deimos
  module Utils
    # Mostly copied from Phobos::Executor. We should DRY this up by putting in a
    # PR to make it more generic. Might even make sense to move to a separate
    # gem.
    class Executor
      # @return [Array<#start, #stop, #id>]
      attr_accessor :runners

      # @param runners [Array<#start, #stop, #id>] A list of objects that can be
      # started or stopped.
      # @param logger [Logger]
      def initialize(runners, logger=Logger.new(STDOUT))
        @threads = Concurrent::Array.new
        @runners = runners
        @logger = logger
      end

      # Start the executor.
      def start
        @logger.info('Starting executor')
        @signal_to_stop = false
        @threads.clear
        @thread_pool = Concurrent::FixedThreadPool.new(@runners.size)

        @runners.each do |runner|
          @thread_pool.post do
            thread = Thread.current
            thread.abort_on_exception = true
            @threads << thread
            run_object(runner)
          end
        end

        true
      end

      # Stop the executor.
      def stop
        return if @signal_to_stop

        @logger.info('Stopping executor')
        @signal_to_stop = true
        @runners.each(&:stop)
        @threads.select(&:alive?).each do |thread|
          begin
            thread.wakeup
          rescue StandardError
            nil
          end
        end
        @thread_pool&.shutdown
        @thread_pool&.wait_for_termination
        @logger.info('Executor stopped')
      end

    private

      # @param exception [Throwable]
      # @return [Hash]
      def error_metadata(exception)
        {
          exception_class: exception.class.name,
          exception_message: exception.message,
          backtrace: exception.backtrace
        }
      end

      def run_object(runner)
        retry_count = 0

        begin
          @logger.info("Running #{runner.id}")
          runner.start
          retry_count = 0 # success - reset retry count
        rescue Exception => e
          handle_crashed_runner(runner, e, retry_count)
          retry_count += 1
          retry unless @signal_to_stop
        end
      rescue Exception => e
        @logger.error("Failed to run listener (#{e.message}) #{error_metadata(e)}")
        raise e
      end

      # @return [ExponentialBackoff]
      def create_exponential_backoff
        min = 1
        max = 60
        ExponentialBackoff.new(min, max).tap do |backoff|
          backoff.randomize_factor = rand
        end
      end

      # When "runner#start" is interrupted / crashes we assume it's
      # safe to be called again
      def handle_crashed_runner(runner, error, retry_count)
        backoff = create_exponential_backoff
        interval = backoff.interval_at(retry_count).round(2)

        metadata = {
          listener_id: runner.id,
          retry_count: retry_count,
          waiting_time: interval
        }.merge(error_metadata(error))

        @logger.error("Runner crashed, waiting #{interval}s (#{error.message}) #{metadata}")
        sleep(interval)
      end
    end
  end
end

# rubocop:enable Lint/RescueException
