# frozen_string_literal: true

module Vizcore
  module Server
    class FrameBroadcaster
      FRAME_RATE = 60.0
      FRAME_INTERVAL = 1.0 / FRAME_RATE

      def initialize(scene_name: "basic")
        @scene_name = scene_name
        @running = false
        @thread = nil
        @beat_count = 0
      end

      def start
        return if running?

        @running = true
        started_at = monotonic_time
        @thread = Thread.new { run_loop(started_at) }
      end

      def stop
        return unless running?

        @running = false
        thread = @thread
        @thread = nil
        thread&.join(1.0)
      end

      def running?
        @running
      end

      def build_frame(elapsed_seconds)
        amplitude = ((Math.sin(elapsed_seconds * 2.0) + 1.0) / 2.0).clamp(0.0, 1.0)
        bass = ((Math.sin(elapsed_seconds * 1.1) + 1.0) / 2.0).clamp(0.0, 1.0)
        mid = ((Math.sin(elapsed_seconds * 1.7 + 1.2) + 1.0) / 2.0).clamp(0.0, 1.0)
        high = ((Math.sin(elapsed_seconds * 2.3 + 2.5) + 1.0) / 2.0).clamp(0.0, 1.0)

        beat = amplitude > 0.96
        @beat_count += 1 if beat

        {
          timestamp: Time.now.to_f,
          audio: {
            amplitude: amplitude.round(4),
            bands: {
              sub: (bass * 0.75).round(4),
              low: bass.round(4),
              mid: mid.round(4),
              high: high.round(4)
            },
            fft: Array.new(32) { |index| ((Math.sin(elapsed_seconds + index * 0.2) + 1.0) / 2.0).round(4) },
            beat: beat,
            beat_count: @beat_count,
            bpm: 128.0
          },
          scene: {
            name: @scene_name,
            layers: [
              {
                name: "wireframe_cube",
                type: "geometry",
                params: {
                  rotation_speed: (0.4 + amplitude * 1.5).round(4),
                  color_shift: high.round(4)
                }
              }
            ]
          },
          transition: nil
        }
      end

      private

      def run_loop(started_at)
        while running?
          loop_started = monotonic_time
          elapsed = loop_started - started_at
          frame = build_frame(elapsed)
          WebSocketHandler.broadcast(type: "audio_frame", payload: frame)

          duration = monotonic_time - loop_started
          sleep_time = FRAME_INTERVAL - duration
          sleep(sleep_time) if sleep_time.positive?
        end
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
