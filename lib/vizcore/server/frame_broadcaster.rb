# frozen_string_literal: true

require_relative "../audio"

module Vizcore
  module Server
    class FrameBroadcaster
      FRAME_RATE = 60.0
      FRAME_INTERVAL = 1.0 / FRAME_RATE

      def initialize(scene_name: "basic", input_manager: nil)
        @scene_name = scene_name
        @input_manager = input_manager || Vizcore::Audio::InputManager.new(source: :mic)
        @running = false
        @thread = nil
        @beat_count = 0
      end

      def start
        return if running?

        @input_manager.start
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
        @input_manager.stop
      end

      def running?
        @running
      end

      def build_frame(_elapsed_seconds, samples = nil)
        audio_samples = samples || capture_samples
        amplitude = rms(audio_samples)
        bands = split_bands(audio_samples)
        bass = bands[:low]
        mid = bands[:mid]
        high = bands[:high]

        beat = amplitude > 0.72
        @beat_count += 1 if beat

        {
          timestamp: Time.now.to_f,
          audio: {
            amplitude: amplitude.round(4),
            bands: bands.transform_values { |value| value.round(4) },
            fft: fft_preview(audio_samples),
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
          samples = capture_samples
          frame = build_frame(elapsed, samples)
          WebSocketHandler.broadcast(type: "audio_frame", payload: frame)

          duration = monotonic_time - loop_started
          sleep_time = FRAME_INTERVAL - duration
          sleep(sleep_time) if sleep_time.positive?
        end
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def capture_samples
        samples = @input_manager.capture_frame
        samples.empty? ? Array.new(@input_manager.frame_size, 0.0) : samples
      rescue StandardError
        Array.new(1024, 0.0)
      end

      def split_bands(samples)
        abs = samples.map { |sample| sample.abs.clamp(0.0, 1.0) }
        chunk_size = [abs.length / 4, 1].max
        sub = average(abs[0, chunk_size]) * 0.7
        low = average(abs[chunk_size, chunk_size])
        mid = average(abs[chunk_size * 2, chunk_size])
        high = average(abs[chunk_size * 3, chunk_size])

        { sub: sub, low: low, mid: mid, high: high }
      end

      def fft_preview(samples)
        values = samples.map { |sample| sample.abs.clamp(0.0, 1.0) }
        step = [values.length / 32, 1].max

        Array.new(32) do |index|
          window = values[index * step, step]
          average(window).round(4)
        end
      end

      def rms(samples)
        return 0.0 if samples.empty?

        sum = samples.reduce(0.0) { |acc, sample| acc + (sample * sample) }
        Math.sqrt(sum / samples.length.to_f).clamp(0.0, 1.0)
      end

      def average(values)
        normalized = Array(values).compact
        return 0.0 if normalized.empty?

        normalized.sum / normalized.length.to_f
      end
    end
  end
end
