# frozen_string_literal: true

require_relative "../analysis"
require_relative "../audio"
require_relative "../dsl"

module Vizcore
  module Renderer
    # Produces analyzed scene frames for offline renderers.
    class SceneFrameSource
      def initialize(config:, frame_rate: nil)
        @config = config
        @frame_rate = frame_rate
        @shader_source_resolver = Vizcore::DSL::ShaderSourceResolver.new
      end

      # @return [Vizcore::Renderer::SceneFrameSource]
      def start
        @definition = resolve_shader_sources(Vizcore::DSL::Engine.load_file(@config.scene_file.to_s))
        @scene = first_scene(@definition)
        @input_manager = build_input_manager
        @input_manager.start
        @capture_size = capture_size
        @pipeline = build_pipeline
        @frame_count = 0
        self
      end

      # @return [Hash] frame data consumed by offline renderers
      def capture
        ensure_started!

        audio = @pipeline.call(@input_manager.capture_frame(@capture_size))
        @frame_count += 1
        layers = Vizcore::DSL::MappingResolver.new.resolve_layers(
          scene_layers: @scene[:layers],
          audio: audio,
          time: frame_time,
          frame: @frame_count
        )

        {
          scene: { name: @scene[:name], layers: layers },
          audio: audio,
          scene_name: @scene[:name].to_s
        }
      end

      # @return [void]
      def stop
        @input_manager&.stop
      end

      private

      def resolve_shader_sources(definition)
        @shader_source_resolver.resolve(definition: definition, scene_file: @config.scene_file.to_s)
      end

      def first_scene(definition)
        scene = Array(definition[:scenes]).first
        return scene if scene

        { name: @config.scene_file.basename(".rb").to_sym, layers: [] }
      end

      def build_input_manager
        Vizcore::Audio::InputManager.new(
          source: @config.audio_source,
          file_path: @config.audio_file&.to_s,
          audio_device: @config.audio_device
        )
      end

      def capture_size
        return @input_manager.frame_size unless @frame_rate

        @input_manager.realtime_capture_size(@frame_rate)
      end

      def build_pipeline
        Vizcore::Analysis::Pipeline.new(
          sample_rate: @input_manager.sample_rate,
          fft_size: supported_fft_size(@input_manager.frame_size),
          noise_gate: @config.noise_gate,
          audio_normalize: audio_normalize_settings,
          bpm: bpm_setting,
          bpm_lock: bpm_lock_setting
        )
      end

      def frame_time
        return 0.0 unless @frame_rate

        (@frame_count - 1).fdiv(@frame_rate)
      end

      def audio_normalize_settings
        Hash(@definition[:analysis] || {})[:audio_normalize]
      rescue StandardError
        nil
      end

      def bpm_setting
        @config.bpm || Hash(@definition[:analysis] || {})[:bpm]
      rescue StandardError
        @config.bpm
      end

      def bpm_lock_setting
        @config.bpm_lock? || !!Hash(@definition[:analysis] || {})[:bpm_lock]
      rescue StandardError
        @config.bpm_lock?
      end

      def supported_fft_size(size)
        value = Integer(size)
        return value if value.positive? && (value & (value - 1)).zero?

        1024
      rescue StandardError
        1024
      end

      def ensure_started!
        return if @input_manager && @pipeline && @scene

        raise RuntimeError, "scene frame source has not been started"
      end
    end
  end
end
