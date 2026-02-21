# frozen_string_literal: true

module Vizcore
  module Renderer
    # Fixed-interval scheduler used by the frame broadcast loop.
    class FrameScheduler
      # Default frame rate used by renderer loops.
      DEFAULT_FRAME_RATE = 60.0

      # @param frame_rate [Float]
      # @param monotonic_clock [#call, nil]
      # @param sleeper [#call, nil]
      # @param error_handler [#call, nil]
      # @yieldparam elapsed [Float]
      def initialize(frame_rate: DEFAULT_FRAME_RATE, monotonic_clock: nil, sleeper: nil, error_handler: nil, &on_tick)
        @frame_rate = Float(frame_rate)
        raise ArgumentError, "frame_rate must be positive" unless @frame_rate.positive?

        @frame_interval = 1.0 / @frame_rate
        @monotonic_clock = monotonic_clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @sleeper = sleeper || ->(seconds) { sleep(seconds) }
        @error_handler = error_handler || ->(error) { raise error }
        @on_tick = on_tick
        @running = false
        @thread = nil
      end

      # @return [void]
      def start
        return if running?

        @running = true
        started_at = @monotonic_clock.call
        @thread = Thread.new { run_loop(started_at) }
      end

      # @param timeout [Float]
      # @return [void]
      def stop(timeout: 1.0)
        return unless running?

        @running = false
        thread = @thread
        @thread = nil
        return unless thread
        return if thread == Thread.current

        thread.join(timeout)
      end

      # @return [Boolean]
      def running?
        @running
      end

      private

      def run_loop(started_at)
        while running?
          begin
            loop_started = @monotonic_clock.call
            elapsed = loop_started - started_at
            @on_tick&.call(elapsed)

            duration = @monotonic_clock.call - loop_started
            sleep_time = @frame_interval - duration
            @sleeper.call(sleep_time) if sleep_time.positive?
          rescue StandardError => e
            @error_handler.call(e)
          end
        end
      end
    end
  end
end
