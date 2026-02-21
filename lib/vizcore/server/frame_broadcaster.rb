# frozen_string_literal: true

require_relative "../audio"
require_relative "../analysis"

module Vizcore
  module Server
    class FrameBroadcaster
      FRAME_RATE = 60.0
      FRAME_INTERVAL = 1.0 / FRAME_RATE

      def initialize(scene_name: "basic", scene_layers: nil, input_manager: nil, analysis_pipeline: nil)
        @scene_name = scene_name
        @scene_layers = normalize_scene_layers(scene_layers)
        @input_manager = input_manager || Vizcore::Audio::InputManager.new(source: :mic)
        fft_size = supported_fft_size(@input_manager.frame_size)
        @analysis_pipeline = analysis_pipeline || Vizcore::Analysis::Pipeline.new(
          sample_rate: @input_manager.sample_rate,
          fft_size: fft_size
        )
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

        @scene_layers.map { |layer| build_layer(layer, analyzed) }
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

      def build_layer(layer, analyzed)
        params = (layer[:params] || {}).dup
        params.merge!(resolve_mappings(layer[:mappings], analyzed))

        output = {
          name: layer.fetch(:name).to_s,
          type: (layer[:type] || :geometry).to_s,
          params: params
        }
        output[:shader] = layer[:shader].to_s if layer[:shader]
        output[:glsl] = layer[:glsl].to_s if layer[:glsl]
        output
      end

      def resolve_mappings(mappings, analyzed)
        Array(mappings).each_with_object({}) do |mapping, resolved|
          source = mapping[:source]
          target = mapping[:target]
          next unless source && target

          value = resolve_source_value(source, analyzed)
          resolved[target.to_sym] = value unless value.nil?
        end
      end

      def resolve_source_value(source, analyzed)
        kind = source[:kind]&.to_sym
        case kind
        when :amplitude
          analyzed[:amplitude]
        when :frequency_band
          analyzed.dig(:bands, source[:band]&.to_sym)
        when :fft_spectrum
          analyzed[:fft]
        when :beat
          analyzed[:beat]
        when :beat_count
          analyzed[:beat_count]
        when :bpm
          analyzed[:bpm]
        else
          nil
        end
      end

      def normalize_scene_layers(scene_layers)
        Array(scene_layers).map { |layer| deep_symbolize(layer) }
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, entry), output|
            output[key.to_sym] = deep_symbolize(entry)
          end
        when Array
          value.map { |entry| deep_symbolize(entry) }
        else
          value
        end
      end
    end
  end
end
