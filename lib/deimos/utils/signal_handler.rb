# frozen_string_literal: true

module Deimos
  module Utils
    # Mostly copied free-form from Phobos::Cli::Runner. We should add a PR to
    # basically replace that implementation with this one to make it more generic.
    class SignalHandler
      SIGNALS = %i(INT TERM QUIT).freeze

      # Takes any object that responds to the `start` and `stop` methods.
      # @param runner[#start, #stop]
      def initialize(runner)
        @signal_queue = []
        @reader, @writer = IO.pipe
        @runner = runner
      end

      # Run the runner.
      def run!
        setup_signals
        @runner.start

        loop do
          case signal_queue.pop
          when *SIGNALS
            @runner.stop
            break
          else
            ready = IO.select([reader, writer])

            # drain the self-pipe so it won't be returned again next time
            reader.read_nonblock(1) if ready[0].include?(reader)
          end
        end
      end

    private

      attr_reader :reader, :writer, :signal_queue, :executor

      # https://stackoverflow.com/questions/29568298/run-code-when-signal-is-sent-but-do-not-trap-the-signal-in-ruby
      def prepend_handler(signal)
        previous = Signal.trap(signal) do
          unless previous.respond_to?(:call)
            previous = -> { raise SignalException, signal }
          end
          yield
          previous.call
        end
      end

      # Trap signals using the self-pipe trick.
      def setup_signals
        at_exit { @runner&.stop }
        SIGNALS.each do |signal|
          prepend_handler(signal) do
            unblock(signal)
          end
        end
      end

      # Save the signal to the queue and continue on.
      # @param signal [Symbol]
      def unblock(signal)
        writer.write_nonblock('.')
        signal_queue << signal
      end
    end
  end
end
