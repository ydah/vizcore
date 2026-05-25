# frozen_string_literal: true

require_relative "../analysis"
require_relative "../audio"
require_relative "../dsl"

module Vizcore
  module Renderer
    # Produces analyzed scene frames for offline renderers.
    class SceneFrameSource
      def initialize(config:, frame_rate: nil, seed: nil)
        @config = config
        @frame_rate = frame_rate
        @seed = seed
        @shader_source_resolver = Vizcore::DSL::ShaderSourceResolver.new
      end

      # @return [Vizcore::Renderer::SceneFrameSource]
      def start
        @definition = resolve_shader_sources(Vizcore::DSL::Engine.load_file(@config.scene_file.to_s))
        apply_seed!
        scenes = Array(@definition[:scenes])
        initial_timeline_entry = initial_timeline_entry(@definition)
        @scene = resolve_initial_scene(scenes, initial_timeline_entry)
        @transition_controller = Vizcore::DSL::TransitionController.new(
          scenes: scenes,
          transitions: Array(@definition[:transitions]),
          error_reporter: lambda do |message|
            report_transition_error(message)
          end
        )
        @mapping_resolver = Vizcore::DSL::MappingResolver.new
        @input_manager = build_input_manager
        @input_manager.start
        @capture_size = capture_size
        @pipeline = build_pipeline
        @frame_count = 0
        @scene_frame_base = 0
        @scene_elapsed_base = 0.0
        @scene_beat_base = 0
        align_timeline_start(entry: initial_timeline_entry)
        self
      end

      # @return [Hash] frame data consumed by offline renderers
      def capture
        ensure_started!

        audio = @pipeline.call(@input_manager.capture_frame(@capture_size))
        @frame_count += 1
        scene = @scene
        layers = @mapping_resolver.resolve_layers(
          scene_layers: scene[:layers],
          audio: audio,
          time: frame_time,
          frame: @frame_count
        )
        evaluate_transition(audio)

        {
          scene: {
            schema_version: Vizcore::Renderer::SceneSerializer::SCENE_SCHEMA_VERSION,
            name: scene[:name],
            layers: layers
          },
          audio: audio,
          scene_name: scene[:name].to_s
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

      def apply_seed!
        seed = @seed || @definition[:seed]
        return if seed.nil?

        Kernel.srand(Integer(seed))
      rescue ArgumentError, TypeError
        raise ArgumentError, "render seed must be an integer"
      end

      def first_scene(definition)
        scene = Array(definition[:scenes]).first
        return scene if scene

        { name: @config.scene_file.basename(".rb").to_sym, layers: [] }
      end

      def initial_timeline_entry(definition)
        timelines = Array(definition[:timelines])
        timelines.each do |timeline|
          first_entry = Array(timeline).first
          return first_entry if first_entry
        end

        nil
      end

      def resolve_initial_scene(scenes, initial_timeline_entry)
        scene_name = initial_timeline_entry&.dig(:scene)
        scene = scenes.find { |entry| entry[:name].to_s == scene_name.to_s } if scene_name
        scene || first_scene({ scenes: scenes })
      end

      def align_timeline_start(entry:)
        return unless entry

        unit = entry[:unit].to_s
        start_position = Float(entry[:at] || 0.0)
        return unless start_position.positive?

        @scene_elapsed_base = start_position if unit == "seconds"
        @scene_beat_base = Integer(start_position) if unit == "beats"
      rescue StandardError
        nil
      end

      def evaluate_transition(audio)
        transition = @transition_controller.next_transition(
          scene_name: @scene[:name],
          audio: transition_audio(audio),
          frame_count: scene_frame_count,
          elapsed_seconds: scene_elapsed_seconds
        )
        return unless transition

        @scene = transition.fetch(:scene)
        reset_scene_counters(audio)
      end

      def transition_audio(audio)
        audio_hash = Hash(audio)
        scene_count = scene_beat_count(audio_hash)
        audio_hash.merge(scene_musical_counts(audio_hash, beat_count: scene_count))
      rescue StandardError
        { beat_count: 0 }
      end

      def scene_frame_count
        [@frame_count - @scene_frame_base, 0].max
      end

      def scene_elapsed_seconds
        [frame_time - @scene_elapsed_base, 0.0].max
      end

      def scene_beat_count(audio)
        global_beat_count = Integer(Hash(audio)[:beat_count] || 0)
        [global_beat_count - @scene_beat_base, 0].max
      rescue StandardError
        0
      end

      def reset_scene_counters(audio)
        audio_hash = Hash(audio)
        @scene_frame_base = @frame_count
        @scene_elapsed_base = frame_time
        @scene_beat_base = Integer(audio_hash[:beat_count] || 0) - (audio_hash[:beat] ? 1 : 0)
      rescue StandardError
        @scene_frame_base = @frame_count
        @scene_elapsed_base = frame_time
        @scene_beat_base = 0
      end

      def scene_musical_counts(audio, beat_count:)
        beat_index = beat_count.positive? ? beat_count - 1 : 0
        beat_phase = Float(audio[:beat_phase] || audio["beat_phase"] || 0.0).clamp(0.0, 1.0)
        {
          beat_count: beat_count,
          bar_phase: (((beat_index % 4) + beat_phase) / 4.0).clamp(0.0, 1.0),
          bar_count: beat_index / 4,
          phrase_count: beat_index / 32
        }
      rescue StandardError
        { beat_count: beat_count, bar_phase: 0.0, bar_count: 0, phrase_count: 0 }
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

      def report_transition_error(message)
        warn(message)
      end

      def build_pipeline
        Vizcore::Analysis::Pipeline.new(
          sample_rate: @input_manager.sample_rate,
          fft_size: supported_fft_size(@input_manager.frame_size),
          noise_gate: @config.noise_gate,
          audio_normalize: audio_normalize_settings,
          bpm: bpm_setting,
          bpm_lock: bpm_lock_setting,
          onset_sensitivity: analysis_setting(:onset_sensitivity, 1.0),
          fft_preview_bins: analysis_setting(:fft_bins, Vizcore::Analysis::Pipeline::DEFAULT_FFT_PREVIEW_BINS),
          peak_hold_frames: analysis_setting(:peak_hold_frames, 0),
          silence_reset_frames: analysis_setting(:silence_reset_frames, Vizcore::Analysis::Pipeline::SILENCE_RESET_FRAMES)
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

      def analysis_setting(key, fallback)
        Hash(@definition[:analysis] || {}).fetch(key, fallback)
      rescue StandardError
        fallback
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
