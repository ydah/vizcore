# frozen_string_literal: true

require_relative "../audio"
require_relative "../analysis"
require_relative "../dsl"

module Vizcore
  module Server
    class FrameBroadcaster
      FRAME_RATE = 60.0
      FRAME_INTERVAL = 1.0 / FRAME_RATE

      def initialize(
        scene_name: "basic",
        scene_layers: nil,
        input_manager: nil,
        analysis_pipeline: nil,
        mapping_resolver: nil
      )
        @scene_name = scene_name
        @scene_layers = Array(scene_layers)
        @input_manager = input_manager || Vizcore::Audio::InputManager.new(source: :mic)
        fft_size = supported_fft_size(@input_manager.frame_size)
        @analysis_pipeline = analysis_pipeline || Vizcore::Analysis::Pipeline.new(
          sample_rate: @input_manager.sample_rate,
          fft_size: fft_size
        )
        @mapping_resolver = mapping_resolver || Vizcore::DSL::MappingResolver.new
        @running = false
        @thread = nil
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
        analyzed = @analysis_pipeline.call(audio_samples)
        layers = build_scene_layers(analyzed)

        {
          timestamp: Time.now.to_f,
          audio: {
            amplitude: analyzed[:amplitude].round(4),
            bands: analyzed[:bands].transform_values { |value| value.round(4) },
            fft: analyzed[:fft].map { |value| value.round(4) },
            beat: analyzed[:beat],
            beat_count: analyzed[:beat_count],
            bpm: analyzed[:bpm]
          },
          scene: {
            name: @scene_name,
            layers: layers
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

      def supported_fft_size(size)
        value = Integer(size)
        return value if power_of_two?(value)

        1024
      rescue StandardError
        1024
      end

      def power_of_two?(value)
        value.positive? && (value & (value - 1)).zero?
      end

      def build_scene_layers(analyzed)
        return default_scene_layers(analyzed) if @scene_layers.empty?

        @mapping_resolver.resolve_layers(scene_layers: @scene_layers, audio: analyzed)
      end

      def default_scene_layers(analyzed)
        amplitude = analyzed[:amplitude]
        high = analyzed.dig(:bands, :high).to_f

        [
          {
            name: "wireframe_cube",
            type: "geometry",
            params: {
              rotation_speed: (0.4 + amplitude * 1.5).round(4),
              color_shift: high.round(4)
            }
          }
        ]
      end

    end
  end
end
