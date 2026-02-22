# frozen_string_literal: true

require_relative "../audio"
require_relative "../analysis"
require_relative "../dsl"
require_relative "../errors"
require_relative "../renderer"

module Vizcore
  module Server
    # Produces audio-reactive frame payloads and broadcasts them over WebSocket.
    class FrameBroadcaster
      # Target broadcast frame rate.
      FRAME_RATE = 60.0

      # @param scene_name [String]
      # @param scene_layers [Array<Hash>, nil]
      # @param input_manager [Vizcore::Audio::InputManager, nil]
      # @param analysis_pipeline [Vizcore::Analysis::Pipeline, nil]
      # @param mapping_resolver [Vizcore::DSL::MappingResolver, nil]
      # @param scene_serializer [Vizcore::Renderer::SceneSerializer, nil]
      # @param frame_scheduler [Vizcore::Renderer::FrameScheduler, nil]
      # @param scene_catalog [Array<Hash>, nil]
      # @param transitions [Array<Hash>, nil]
      # @param transition_controller [Vizcore::DSL::TransitionController, nil]
      # @param error_reporter [#call, nil]
      def initialize(
        scene_name: "basic",
        scene_layers: nil,
        input_manager: nil,
        analysis_pipeline: nil,
        mapping_resolver: nil,
        scene_serializer: nil,
        frame_scheduler: nil,
        scene_catalog: nil,
        transitions: nil,
        transition_controller: nil,
        error_reporter: nil
      )
        @scene_name = scene_name
        @scene_layers = Array(scene_layers)
        @scene_mutex = Mutex.new
        @input_manager = input_manager || Vizcore::Audio::InputManager.new(source: :mic)
        fft_size = supported_fft_size(@input_manager.frame_size)
        @analysis_pipeline = analysis_pipeline || Vizcore::Analysis::Pipeline.new(
          sample_rate: @input_manager.sample_rate,
          fft_size: fft_size
        )
        @mapping_resolver = mapping_resolver || Vizcore::DSL::MappingResolver.new
        @scene_serializer = scene_serializer || Vizcore::Renderer::SceneSerializer.new
        @transition_controller = transition_controller || Vizcore::DSL::TransitionController.new(
          scenes: scene_catalog || [],
          transitions: transitions || []
        )
        @error_reporter = error_reporter || ->(_message) {}
        @last_error = nil
        @frame_count = 0
        @transport_playing = initial_transport_playing_state
        reset_transition_trigger_counters!
        @frame_scheduler = frame_scheduler || Vizcore::Renderer::FrameScheduler.new(frame_rate: FRAME_RATE) do |elapsed|
          tick(elapsed)
        end
      end

      attr_reader :last_error

      # @return [void]
      def start
        return if running?

        @input_manager.start
        @frame_scheduler.start
      rescue StandardError => e
        report_error(e, context: "frame broadcaster start failed")
        @input_manager.stop
        raise
      end

      # @return [void]
      def stop
        return unless running?

        @frame_scheduler.stop
        @input_manager.stop
      end

      # @return [Boolean]
      def running?
        @frame_scheduler.running?
      end

      # @return [Hash] current scene snapshot (`name`, `layers`)
      def current_scene_snapshot
        current_scene
      end

      # Synchronize external playback transport (e.g. browser audio element) with the input source.
      #
      # @param playing [Boolean]
      # @param position_seconds [Numeric]
      # @return [void]
      def sync_transport(playing:, position_seconds:)
        @scene_mutex.synchronize do
          @transport_playing = !!playing
          reset_transition_trigger_counters! if transport_position_reset?(position_seconds)
        end
        return unless @input_manager.respond_to?(:sync_transport)

        @input_manager.sync_transport(playing: playing, position_seconds: position_seconds)
      rescue StandardError => e
        report_error(e, context: "audio transport sync failed")
      end

      # Run one frame tick and broadcast it.
      #
      # @param elapsed_seconds [Float]
      # @param samples [Array<Float>, nil]
      # @return [Hash] serialized frame
      def tick(elapsed_seconds, samples = nil)
        @frame_count += 1
        frame = build_frame(elapsed_seconds, samples)
        WebSocketHandler.broadcast(type: "audio_frame", payload: frame)
        evaluate_transition(frame[:audio], frame_count: @frame_count)
        frame
      end

      # Replace active scene and layers.
      #
      # @param scene_name [String, Symbol]
      # @param scene_layers [Array<Hash>]
      # @return [void]
      def update_scene(scene_name:, scene_layers:)
        @scene_mutex.synchronize do
          @scene_name = scene_name.to_s
          @scene_layers = Array(scene_layers)
          reset_transition_trigger_counters!
        end
      end

      # Replace transition catalog used by automatic scene switching.
      #
      # @param scenes [Array<Hash>]
      # @param transitions [Array<Hash>]
      # @return [void]
      def update_transition_definition(scenes:, transitions:)
        @scene_mutex.synchronize do
          @transition_controller.update(scenes: scenes, transitions: transitions)
        end
      end

      # Build one frame payload for transport to frontend.
      #
      # @param _elapsed_seconds [Float]
      # @param samples [Array<Float>, nil]
      # @raise [Vizcore::FrameBuildError] when frame construction fails
      # @return [Hash]
      def build_frame(_elapsed_seconds, samples = nil)
        audio_samples = samples || capture_samples
        analyzed = @analysis_pipeline.call(audio_samples)
        scene = current_scene
        layers = build_scene_layers(scene[:layers], analyzed)

        @scene_serializer.audio_frame(
          timestamp: Time.now.to_f,
          audio: analyzed,
          scene_name: scene[:name],
          scene_layers: layers,
          transition: nil
        )
      rescue StandardError => e
        report_error(e, context: "frame build failed")
        raise Vizcore::FrameBuildError, Vizcore::ErrorFormatting.summarize(e, context: "Frame build failed")
      end

      private

      def capture_samples
        ingest_count =
          if @input_manager.respond_to?(:realtime_capture_size)
            @input_manager.realtime_capture_size(FRAME_RATE)
          else
            @input_manager.frame_size
          end

        @input_manager.capture_frame(ingest_count)
        samples = Array(@input_manager.latest_samples(@input_manager.frame_size))
        return samples if samples.length == @input_manager.frame_size
        return Array.new(@input_manager.frame_size, 0.0) if samples.empty?

        Array.new(@input_manager.frame_size - samples.length, 0.0) + samples
      rescue StandardError => e
        report_error(e, context: "audio capture failed")
        fallback_frame_size = @input_manager.respond_to?(:frame_size) ? Integer(@input_manager.frame_size) : 1024
        Array.new(fallback_frame_size, 0.0)
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

      def build_scene_layers(scene_layers, analyzed)
        return default_scene_layers(analyzed) if scene_layers.empty?

        @mapping_resolver.resolve_layers(scene_layers: scene_layers, audio: analyzed)
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

      def current_scene
        @scene_mutex.synchronize do
          {
            name: @scene_name,
            layers: Array(@scene_layers)
          }
        end
      end

      def evaluate_transition(audio, frame_count:)
        return if transition_evaluation_paused?

        transition = @scene_mutex.synchronize do
          scene = {
            name: @scene_name,
            layers: Array(@scene_layers)
          }
          trigger_frame_count, trigger_audio = transition_trigger_inputs(
            scene_name: scene[:name],
            audio: audio,
            frame_count: frame_count
          )
          @transition_controller.next_transition(
            scene_name: scene[:name],
            audio: trigger_audio,
            frame_count: trigger_frame_count
          )
        end
        return unless transition

        update_scene(scene_name: transition[:to], scene_layers: transition.dig(:scene, :layers))
        WebSocketHandler.broadcast(
          type: "scene_change",
          payload: {
            from: transition[:from].to_s,
            to: transition[:to].to_s,
            effect: transition[:effect]
          }
        )
      end

      def reset_transition_trigger_counters!
        @transition_counter_scene_name = nil
        @transition_counter_frame_base = 0
        @transition_counter_beat_base = 0
      end

      def transition_evaluation_paused?
        @scene_mutex.synchronize { file_transport_source? && !@transport_playing }
      end

      def initial_transport_playing_state
        file_transport_source? ? false : true
      end

      def file_transport_source?
        return false unless @input_manager.is_a?(Vizcore::Audio::InputManager)

        @input_manager.source_name.to_sym == :file
      rescue StandardError
        false
      end

      def transport_position_reset?(position_seconds)
        Float(position_seconds) <= 0.05
      rescue StandardError
        false
      end

      def transition_trigger_inputs(scene_name:, audio:, frame_count:)
        sync_transition_trigger_counters(scene_name: scene_name, audio: audio, frame_count: frame_count)

        global_frame_count = Integer(frame_count)
        scene_frame_count = [global_frame_count - @transition_counter_frame_base, 0].max

        audio_hash = Hash(audio)
        global_beat_count = extract_beat_count(audio_hash)
        scene_beat_count = [global_beat_count - @transition_counter_beat_base, 0].max

        [scene_frame_count, audio_hash.merge(beat_count: scene_beat_count)]
      rescue StandardError
        [0, { beat_count: 0 }]
      end

      def sync_transition_trigger_counters(scene_name:, audio:, frame_count:)
        normalized_scene_name = scene_name.to_s
        return if @transition_counter_scene_name == normalized_scene_name

        audio_hash = Hash(audio)
        global_frame_count = Integer(frame_count)
        global_beat_count = extract_beat_count(audio_hash)

        @transition_counter_scene_name = normalized_scene_name
        @transition_counter_frame_base = [global_frame_count - 1, 0].max
        # Include the current frame's beat in the new scene-local counter when a beat is detected.
        @transition_counter_beat_base = global_beat_count - (truthy_audio_beat?(audio_hash) ? 1 : 0)
      rescue StandardError
        reset_transition_trigger_counters!
      end

      def extract_beat_count(audio)
        Integer(audio[:beat_count] || audio["beat_count"] || 0)
      rescue StandardError
        0
      end

      def truthy_audio_beat?(audio)
        !!(audio[:beat] || audio["beat"])
      end

      def report_error(error, context:)
        @last_error = error
        @error_reporter.call(Vizcore::ErrorFormatting.summarize(error, context: context))
      rescue StandardError
        nil
      end

    end
  end
end
