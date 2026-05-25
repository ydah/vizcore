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
      # @param noise_gate [Numeric]
      # @param audio_normalize [Hash, nil]
      # @param bpm [Numeric, nil]
      # @param bpm_lock [Boolean]
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
        noise_gate: Vizcore::Analysis::Pipeline::DEFAULT_NOISE_GATE,
        audio_normalize: nil,
        bpm: nil,
        bpm_lock: false,
        error_reporter: nil
      )
        @scene_name = scene_name
        @scene_layers = Array(scene_layers)
        @scene_mutex = Mutex.new
        @input_manager = input_manager || Vizcore::Audio::InputManager.new(source: :mic)
        fft_size = supported_fft_size(@input_manager.frame_size)
        @analysis_pipeline = analysis_pipeline || Vizcore::Analysis::Pipeline.new(
          sample_rate: @input_manager.sample_rate,
          fft_size: fft_size,
          noise_gate: noise_gate,
          audio_normalize: audio_normalize,
          bpm: bpm,
          bpm_lock: bpm_lock
        )
        @mapping_resolver = mapping_resolver || Vizcore::DSL::MappingResolver.new
        @scene_serializer = scene_serializer || Vizcore::Renderer::SceneSerializer.new
        @error_reporter = error_reporter || ->(_message) {}
        @transition_controller = transition_controller || Vizcore::DSL::TransitionController.new(
          scenes: scene_catalog || [],
          transitions: transitions || [],
          error_reporter: lambda do |message|
            @error_reporter.call(message)
            report_runtime_message(message, context: "transition trigger failed", source: "transition")
          end
        )
        @last_error = nil
        @frame_count = 0
        @last_frame_metrics = {}
        @custom_shape_param_overrides = {}
        @custom_shape_param_mutex = Mutex.new
        @transport_playing = initial_transport_playing_state
        reset_transition_trigger_counters!
        @tap_tempo = Vizcore::Analysis::TapTempo.new
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

      # @return [Hash] runtime health details for control/status endpoints
      def runtime_status
        scene = current_scene
        {
          current_scene: scene[:name].to_s,
          fps: FRAME_RATE,
          frame_id: @frame_count,
          sample_rate: input_manager_value(:sample_rate),
          frame_size: input_manager_value(:frame_size),
          transport_playing: @scene_mutex.synchronize { @transport_playing },
          websocket_clients: WebSocketHandler.connection_count,
          dropped_frames: WebSocketHandler.dropped_frame_count,
          last_error: formatted_last_error,
          metrics: deep_dup(@last_frame_metrics)
        }.compact
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
        evaluate_transition(frame[:audio], frame_count: @frame_count, elapsed_seconds: elapsed_seconds)
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
          @mapping_resolver.reset! if @mapping_resolver.respond_to?(:reset!)
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

      # Replace audio analysis settings after scene hot reload.
      #
      # @param audio_normalize [Hash, nil]
      # @param bpm [Numeric, nil]
      # @param bpm_lock [Boolean]
      # @return [void]
      def update_analysis_settings(audio_normalize:, bpm: nil, bpm_lock: false)
        return unless @analysis_pipeline.respond_to?(:audio_normalize=)

        @analysis_pipeline.audio_normalize = audio_normalize
        @analysis_pipeline.bpm_lock = { bpm: bpm, locked: bpm_lock } if @analysis_pipeline.respond_to?(:bpm_lock=)
      end

      # Apply a manual tap tempo event and lock analysis BPM when enough taps exist.
      #
      # @param timestamp_ms [Numeric]
      # @return [Float, nil]
      def tap_tempo(timestamp_ms:)
        bpm = @tap_tempo.tap(timestamp_ms: timestamp_ms)
        return nil unless bpm
        return bpm unless @analysis_pipeline.respond_to?(:bpm_lock=)

        @analysis_pipeline.bpm_lock = { bpm: bpm, locked: true }
        bpm
      end

      # Lock analysis BPM from an external sync source.
      #
      # @param bpm [Numeric]
      # @return [Float, nil]
      def lock_bpm(bpm)
        numeric = Float(bpm)
        return nil unless numeric.finite? && numeric.positive?
        return numeric unless @analysis_pipeline.respond_to?(:bpm_lock=)

        @analysis_pipeline.bpm_lock = { bpm: numeric, locked: true }
        numeric
      rescue ArgumentError, TypeError
        nil
      end

      # Unlock analysis BPM after an external sync lock.
      #
      # @return [Boolean]
      def unlock_bpm
        @analysis_pipeline.bpm_lock = { bpm: nil, locked: false } if @analysis_pipeline.respond_to?(:bpm_lock=)
        true
      end

      def set_custom_shape_param(layer_name:, custom_shape_index:, param:, value:)
        layer_key = layer_name.to_s
        param_key = param.to_s.strip
        index = Integer(custom_shape_index)
        numeric = finite_float(value)
        return custom_shape_param_overrides_snapshot if layer_key.empty? || param_key.empty? || index.negative? || numeric.nil?

        @custom_shape_param_mutex.synchronize do
          @custom_shape_param_overrides[layer_key] ||= {}
          @custom_shape_param_overrides[layer_key][index] ||= {}
          @custom_shape_param_overrides[layer_key][index][param_key] = numeric
          deep_dup(@custom_shape_param_overrides)
        end
      rescue ArgumentError, TypeError
        custom_shape_param_overrides_snapshot
      end

      # Build one frame payload for transport to frontend.
      #
      # @param _elapsed_seconds [Float]
      # @param samples [Array<Float>, nil]
      # @raise [Vizcore::FrameBuildError] when frame construction fails
      # @return [Hash]
      def build_frame(elapsed_seconds, samples = nil)
        started_at_ms = monotonic_ms
        audio_samples, audio_capture_ms = capture_or_use_samples(samples)
        analyzed, audio_analysis_ms = measure_ms { @analysis_pipeline.call(audio_samples) }
        scene = current_scene
        layers, scene_build_ms = measure_ms { build_scene_layers(scene[:layers], analyzed, time: elapsed_seconds, frame: @frame_count) }

        frame = @scene_serializer.audio_frame(
          timestamp: Time.now.to_f,
          audio: analyzed,
          scene_name: scene[:name],
          scene_layers: layers,
          transition: nil,
          metrics: {
            frame_id: @frame_count,
            audio_capture_ms: audio_capture_ms,
            audio_analysis_ms: audio_analysis_ms,
            scene_build_ms: scene_build_ms,
            server_frame_ms: monotonic_ms - started_at_ms
          }
        )
        @last_frame_metrics = frame[:metrics] || {}
        frame
      rescue StandardError => e
        report_error(e, context: "frame build failed")
        raise Vizcore::FrameBuildError, Vizcore::ErrorFormatting.summarize(e, context: "Frame build failed")
      end

      private

      def capture_or_use_samples(samples)
        return [samples, 0.0] if samples

        measure_ms { capture_samples }
      end

      def input_manager_value(name)
        return nil unless @input_manager.respond_to?(name)

        @input_manager.public_send(name)
      rescue StandardError
        nil
      end

      def formatted_last_error
        error = @last_error
        return nil unless error

        Vizcore::ErrorFormatting.summarize(error, context: "last runtime error")
      rescue StandardError
        error.to_s
      end

      def measure_ms
        started_at = monotonic_ms
        result = yield
        [result, monotonic_ms - started_at]
      end

      def monotonic_ms
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
      end

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

      def build_scene_layers(scene_layers, analyzed, time: 0.0, frame: 0)
        return default_scene_layers(analyzed) if scene_layers.empty?

        @mapping_resolver.resolve_layers(
          scene_layers: scene_layers,
          audio: analyzed,
          time: time,
          frame: frame,
          custom_shape_overrides: custom_shape_param_overrides_snapshot
        )
      end

      def custom_shape_param_overrides_snapshot
        @custom_shape_param_mutex.synchronize { deep_dup(@custom_shape_param_overrides) }
      end

      def finite_float(value)
        numeric = Float(value)
        return nil unless numeric.finite?

        numeric
      rescue ArgumentError, TypeError
        nil
      end

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, entry), output| output[key] = deep_dup(entry) }
        when Array
          value.map { |entry| deep_dup(entry) }
        else
          value
        end
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

      def evaluate_transition(audio, frame_count:, elapsed_seconds:)
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
          trigger_elapsed_seconds = transition_trigger_elapsed_seconds(
            scene_name: scene[:name],
            elapsed_seconds: elapsed_seconds
          )
          @transition_controller.next_transition(
            scene_name: scene[:name],
            audio: trigger_audio,
            frame_count: trigger_frame_count,
            elapsed_seconds: trigger_elapsed_seconds
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
        @transition_counter_elapsed_scene_name = nil
        @transition_counter_frame_base = 0
        @transition_counter_beat_base = 0
        @transition_counter_elapsed_base = 0.0
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

        [scene_frame_count, audio_hash.merge(scene_musical_counts(audio_hash, beat_count: scene_beat_count))]
      rescue StandardError
        [0, { beat_count: 0 }]
      end

      def transition_trigger_elapsed_seconds(scene_name:, elapsed_seconds:)
        sync_transition_elapsed_counter(scene_name: scene_name, elapsed_seconds: elapsed_seconds)

        current_elapsed = Float(elapsed_seconds)
        [current_elapsed - @transition_counter_elapsed_base, 0.0].max
      rescue StandardError
        0.0
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

      def sync_transition_elapsed_counter(scene_name:, elapsed_seconds:)
        normalized_scene_name = scene_name.to_s
        return if @transition_counter_elapsed_scene_name == normalized_scene_name

        @transition_counter_elapsed_scene_name = normalized_scene_name
        @transition_counter_elapsed_base = Float(elapsed_seconds)
      rescue StandardError
        @transition_counter_elapsed_base = 0.0
      end

      def extract_beat_count(audio)
        Integer(audio[:beat_count] || audio["beat_count"] || 0)
      rescue StandardError
        0
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

      def truthy_audio_beat?(audio)
        !!(audio[:beat] || audio["beat"])
      end

      def report_error(error, context:)
        @last_error = error
        message = Vizcore::ErrorFormatting.summarize(error, context: context)
        @error_reporter.call(message)
        report_runtime_message(message, context: context, source: "runtime")
      rescue StandardError
        nil
      end

      def report_runtime_message(message, context:, source:)
        WebSocketHandler.broadcast(
          type: "runtime_error",
          payload: {
            source: source,
            context: context,
            message: message.to_s,
            frame_id: @frame_count
          }
        )
      rescue StandardError
        nil
      end

    end
  end
end
