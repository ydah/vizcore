# frozen_string_literal: true

require_relative "../audio"
require_relative "../analysis"
require_relative "../dsl"
require_relative "../errors"
require_relative "../renderer"

module Vizcore
  module Server
    class FrameBroadcaster
      FRAME_RATE = 60.0

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
        @frame_scheduler = frame_scheduler || Vizcore::Renderer::FrameScheduler.new(frame_rate: FRAME_RATE) do |elapsed|
          tick(elapsed)
        end
      end

      attr_reader :last_error

      def start
        return if running?

        @input_manager.start
        @frame_scheduler.start
      rescue StandardError => e
        report_error(e, context: "frame broadcaster start failed")
        @input_manager.stop
        raise
      end

      def stop
        return unless running?

        @frame_scheduler.stop
        @input_manager.stop
      end

      def running?
        @frame_scheduler.running?
      end

      def current_scene_snapshot
        current_scene
      end

      def tick(elapsed_seconds, samples = nil)
        frame = build_frame(elapsed_seconds, samples)
        WebSocketHandler.broadcast(type: "audio_frame", payload: frame)
        evaluate_transition(frame[:audio])
        frame
      end

      def update_scene(scene_name:, scene_layers:)
        @scene_mutex.synchronize do
          @scene_name = scene_name.to_s
          @scene_layers = Array(scene_layers)
        end
      end

      def update_transition_definition(scenes:, transitions:)
        @scene_mutex.synchronize do
          @transition_controller.update(scenes: scenes, transitions: transitions)
        end
      end

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
        samples = @input_manager.capture_frame
        samples.empty? ? Array.new(@input_manager.frame_size, 0.0) : samples
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

      def evaluate_transition(audio)
        scene = current_scene
        transition = @scene_mutex.synchronize do
          @transition_controller.next_transition(scene_name: scene[:name], audio: audio)
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

      def report_error(error, context:)
        @last_error = error
        @error_reporter.call(Vizcore::ErrorFormatting.summarize(error, context: context))
      rescue StandardError
        nil
      end

    end
  end
end
