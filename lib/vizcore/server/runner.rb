# frozen_string_literal: true

require "puma"
require_relative "../config"
require_relative "../control_preset"
require_relative "../dsl"
require_relative "../errors"
require_relative "../sync/osc_receiver"
require_relative "frame_broadcaster"
require_relative "rack_app"
require_relative "scene_dependency_watcher"
require_relative "websocket_handler"

module Vizcore
  module Server
    # Bootstraps Rack/Puma, audio pipeline, scene reload, and MIDI runtime.
    class Runner
      DEFAULT_PROFILE_NAME = "default".freeze

      # @param config [Vizcore::Config]
      # @param manifest [Vizcore::ProjectManifest, nil]
      # @param initial_profile [String, nil]
      # @param output [#puts]
      def initialize(config, manifest: nil, initial_profile: nil, output: $stdout)
        @config = config
        @manifest = manifest
        @available_profiles = derive_available_profiles
        @active_profile = normalize_profile_name(initial_profile)
        @active_scene_file = active_scene_file_for_profile(@active_profile)
        @output = output
        @shader_source_resolver = Vizcore::DSL::ShaderSourceResolver.new
        @scene_catalog_mutex = Mutex.new
        @scene_catalog = []
        @scene_watcher = nil
        @osc_schedule_mutex = Mutex.new
        @osc_schedule_threads = []
        @osc_runtime_active = false
        @midi_runtime = nil
        @osc_runtime = nil
        @broadcaster = nil
        @runtime_globals_mutex = Mutex.new
        @runtime_globals = {}
        @live_controls = {
          "blackout" => default_live_control_state,
          "freeze" => default_live_control_state
        }
      end

      # Run server lifecycle until interrupted.
      #
      # @raise [Vizcore::ConfigurationError]
      # @raise [Vizcore::SceneLoadError]
      # @return [void]
      def run
        validate_scene_file!
        validate_public_bind_settings!
        validate_feature_settings!
        validate_control_preset_settings!
        validate_plugin_asset_settings!
        validate_audio_settings!
        definition = load_definition_for_profile(@active_profile)
        control_preset = load_control_preset
        timeline_entry = initial_timeline_entry(definition)
        scene = initial_scene(definition) || fallback_scene
        broadcaster = nil
        app = RackApp.new(
          frontend_root: Vizcore.frontend_root,
          audio_source: runtime_audio_source,
          audio_file: runtime_audio_file,
          scene_names: scene_names_for(definition),
          tap_tempo_key: @tap_tempo_key,
          key_mappings: key_mappings_for(definition),
          globals: runtime_globals_snapshot,
          control_preset: control_preset,
          control_preset_path: @config.control_preset,
          plugin_assets: @config.plugin_assets,
          projector_mode: @config.projector_mode,
          runtime_status_provider: -> { runtime_status_payload }
        )
        server = Puma::Server.new(app, nil, min_threads: 0, max_threads: 4)
        server.add_tcp_listener(@config.host, @config.port)
        server.run

        input_manager = build_input_manager
        warn_if_sample_rate_mismatch(input_manager)
        broadcaster = FrameBroadcaster.new(
          scene_name: scene[:name].to_s,
          scene_layers: scene[:layers],
          scene_catalog: definition[:scenes],
          transitions: definition[:transitions],
          initial_timeline_entry: timeline_entry,
          input_manager: input_manager,
          analysis_pipeline: replay_pipeline,
          noise_gate: @config.noise_gate,
          audio_normalize: audio_normalize_settings(definition),
          bpm: bpm_setting(definition),
          bpm_lock: bpm_lock_setting(definition),
          onset_sensitivity: analysis_setting(definition, :onset_sensitivity, 1.0),
          fft_preview_bins: analysis_setting(definition, :fft_bins, Vizcore::Analysis::Pipeline::DEFAULT_FFT_PREVIEW_BINS),
          peak_hold_frames: analysis_setting(definition, :peak_hold_frames, 0),
          silence_reset_frames: analysis_setting(definition, :silence_reset_frames, Vizcore::Analysis::Pipeline::SILENCE_RESET_FRAMES),
          error_reporter: ->(message) { @output.puts(message) }
        )
        @broadcaster = broadcaster
        configure_runtime_for_definition(definition: definition, broadcaster: broadcaster)
        replace_scene_catalog(definition[:scenes])
        if file_transport_enabled?
          broadcaster.sync_transport(playing: false, position_seconds: 0.0)
        end
        broadcaster.start
        register_client_message_handler(broadcaster)
        @midi_runtime = start_midi_runtime(definition, broadcaster)
        @osc_runtime = start_osc_runtime(broadcaster)
        @scene_watcher = start_scene_watcher(
          broadcaster,
          definition: definition,
          scene_file: active_scene_file
        ) do |reloaded_definition|
          @midi_runtime = refresh_midi_runtime(@midi_runtime, reloaded_definition, broadcaster)
        end if @config.reload?

        @output.puts("Vizcore server listening at http://#{@config.host}:#{@config.port}")
        @output.puts("Projector output: http://#{@config.host}:#{@config.port}/projector")
        @output.puts("Control panel: http://#{@config.host}:#{@config.port}/control")
        @output.puts("Scene: #{scene[:name]}")
        @output.puts("Hot reload: #{@config.reload? ? 'enabled' : 'disabled'}")
        @output.puts("Audio playback: http://#{@config.host}:#{@config.port}/audio-file") if file_transport_enabled?
        @output.puts("Feature replay: #{@config.feature_file}") if feature_replay?
        @output.puts("OSC sync: udp://#{@config.host}:#{@config.osc_port}") if @osc_runtime
        @output.puts("Press Ctrl+C to stop.")

        wait_for_interrupt
      ensure
        Vizcore::Server::WebSocketHandler.clear_message_handler
        stop_osc_runtime(@osc_runtime)
        stop_midi_runtime(@midi_runtime)
        @scene_watcher&.stop
        broadcaster&.stop
        server&.stop(true)
      end

      def warn_if_sample_rate_mismatch(input_manager)
        return unless input_manager.respond_to?(:status)

        status = input_manager.status
        return unless status[:sample_rate_mismatch]

        requested = status[:requested_sample_rate]
        actual = status[:sample_rate]
        return unless requested && actual

        @output.puts(
          "Warning: requested audio sample rate #{requested} does not match device sample rate #{actual}; " \
          "analysis will use #{actual}."
        )
      end

      private

      def derive_available_profiles
        base_profiles = [DEFAULT_PROFILE_NAME]
        manifest_profiles = @manifest ? Array(@manifest.profile_names).map(&:to_s) : []
        all_profiles = (base_profiles + manifest_profiles).map { |profile| normalize_profile_name(profile) }
        all_profiles.uniq
      end

      def normalize_profile_name(value)
        raw = value.to_s.strip
        raw.empty? ? DEFAULT_PROFILE_NAME : raw
      end

      def active_profile_for_api
        @active_profile
      end

      def available_profiles_for_api
        Array(@available_profiles)
      end

      def active_scene_file_for_profile(profile)
        normalized_profile = normalize_profile_name(profile)
        defaults = manifest_config_defaults_for(normalized_profile)
        defaults.fetch(:scene_file, @config.scene_file)
      rescue StandardError
        @config.scene_file
      end

      def manifest_config_defaults_for(profile)
        return {} unless @manifest

        @manifest.config_defaults(profile: profile)
      end

      def active_scene_file
        @active_scene_file
      end

      def active_profile? (candidate)
        active_profile_for_api == normalize_profile_name(candidate)
      end

      def validate_scene_file!
        return if active_scene_file&.file?

        message = if active_scene_file
                    "Scene file not found: #{active_scene_file}"
                  else
                    "Scene file is required"
                  end

        raise Vizcore::ConfigurationError, message
      end

      def load_definition_for_profile(profile)
        scene_file = active_scene_file_for_profile(profile)
        raw_definition = Vizcore::DSL::Engine.load_file(scene_file.to_s)
        resolve_shader_sources(raw_definition, scene_file: scene_file)
      rescue StandardError => e
        raise Vizcore::SceneLoadError, Vizcore::ErrorFormatting.summarize(
          e,
          context: "Failed to load scene file #{scene_file}"
        )
      end

      def load_definition!
        load_definition_for_profile(active_profile_for_api)
      end

      def validate_audio_settings!
        return if feature_replay?
        return unless @config.audio_source == :file
        return if @config.audio_file && @config.audio_file.file?

        raise Vizcore::ConfigurationError, "Audio file not found: #{@config.audio_file || '(nil)'}"
      end

      def validate_public_bind_settings!
        return if @config.allow_public_control?
        return unless public_bind_host?(@config.host)

        raise Vizcore::ConfigurationError,
              "Refusing to expose Vizcore control routes on #{@config.host}; pass --allow-public-control when this is intentional"
      end

      def public_bind_host?(host)
        value = host.to_s.strip
        value.empty? || value == "0.0.0.0" || value == "::" || value == "[::]"
      end

      def validate_feature_settings!
        return unless feature_replay?
        return if @config.feature_file.file?

        raise Vizcore::ConfigurationError, "Feature file not found: #{@config.feature_file}"
      end

      def validate_control_preset_settings!
        return unless @config.control_preset
        return if @config.control_preset.file?

        raise Vizcore::ConfigurationError, "Control preset file not found: #{@config.control_preset}"
      end

      def validate_plugin_asset_settings!
        missing = @config.plugin_assets.find { |path| !path.file? }
        return unless missing

        raise Vizcore::ConfigurationError, "Plugin asset file not found: #{missing}"
      end

      def load_control_preset
        return nil unless @config.control_preset

        Vizcore::ControlPreset.load(@config.control_preset)
      rescue ArgumentError => e
        raise Vizcore::ConfigurationError, e.message
      end

      def build_input_manager
        Vizcore::Audio::InputManager.new(
          source: feature_replay? ? :dummy : @config.audio_source,
          file_path: runtime_audio_file&.to_s,
          audio_device: feature_replay? ? nil : @config.audio_device
        )
      end

      def replay_pipeline
        return nil unless feature_replay?

        Vizcore::Analysis::FeatureReplay.new(path: @config.feature_file)
      end

      def feature_replay?
        !!@config.feature_file
      end

      def file_transport_enabled?
        @config.audio_source == :file && !feature_replay?
      end

      def runtime_audio_source
        feature_replay? ? :features : @config.audio_source
      end

      def runtime_audio_file
        feature_replay? ? nil : @config.audio_file
      end

      def runtime_status_payload
        payload = @broadcaster ? @broadcaster.runtime_status : {}
        payload.merge(
          active_profile: active_profile_for_api,
          available_profiles: available_profiles_for_api
        )
      rescue StandardError
        {
          active_profile: active_profile_for_api,
          available_profiles: available_profiles_for_api
        }
      end

      def configure_runtime_for_definition(definition:, broadcaster: @broadcaster)
        replace_runtime_globals(globals_for(definition))
        @tap_tempo_key = tap_tempo_key(definition)
        broadcaster.update_transition_definition(
          scenes: Array(definition[:scenes]),
          transitions: Array(definition[:transitions])
        )
        broadcaster.update_analysis_settings(
          audio_normalize: audio_normalize_settings(definition),
          bpm: bpm_setting(definition),
          bpm_lock: bpm_lock_setting(definition),
          onset_sensitivity: analysis_setting(definition, :onset_sensitivity, 1.0),
          fft_preview_bins: analysis_setting(definition, :fft_bins, Vizcore::Analysis::Pipeline::DEFAULT_FFT_PREVIEW_BINS),
          peak_hold_frames: analysis_setting(definition, :peak_hold_frames, 0),
          silence_reset_frames: analysis_setting(definition, :silence_reset_frames, Vizcore::Analysis::Pipeline::SILENCE_RESET_FRAMES)
        )
        scene = initial_scene(definition) || fallback_scene
        broadcaster.update_scene(scene_name: scene[:name], scene_layers: scene[:layers])
        scene
      end

      def runtime_config_update_payload(scene:, definition:)
        {
          scene: scene,
          scenes: scene_names_for(definition),
          tap_tempo_key: @tap_tempo_key,
          key_mappings: key_mappings_for(definition),
          globals: runtime_globals_snapshot,
          active_profile: active_profile_for_api,
          available_profiles: available_profiles_for_api
        }
      end

      def broadcast_config_update(scene:, definition:)
        WebSocketHandler.broadcast(
          type: "config_update",
          payload: runtime_config_update_payload(scene: scene, definition: definition)
        )
      end

      def wait_for_interrupt
        stop_requested = false
        %w[INT TERM].each do |signal_name|
          Signal.trap(signal_name) { stop_requested = true }
        rescue ArgumentError
          nil
        end
        sleep(0.1) until stop_requested
      end

      def start_scene_watcher(broadcaster, definition:, scene_file: nil, &on_reload)
        watcher = Vizcore::Server::SceneDependencyWatcher.new(
          scene_file: (scene_file || active_scene_file).to_s,
          definition: definition
        ) do |reloaded_definition, _changed_path|
          reloaded_definition = resolve_shader_sources(reloaded_definition, scene_file: (scene_file || active_scene_file))
          scene = configure_runtime_for_definition(definition: reloaded_definition, broadcaster: broadcaster)
          on_reload&.call(reloaded_definition)
          broadcast_config_update(scene: scene, definition: reloaded_definition)
          @output.puts("Scene reloaded: #{scene[:name]}")
        rescue StandardError => e
          message = Vizcore::ErrorFormatting.summarize(e, context: "Scene reload failed")
          @output.puts(message)
          WebSocketHandler.broadcast(
            type: "runtime_error",
            payload: {
              source: "scene_reload",
              event: "scene_reload_failed",
              context: "Scene reload failed",
              message: message,
              keeping_last_good_scene: true
            }
          )
        end
        watcher.start
        watcher
      rescue StandardError => e
        @output.puts(Vizcore::ErrorFormatting.summarize(e, context: "Scene watcher disabled"))
        nil
      end

      def first_scene(definition)
        definition.fetch(:scenes, []).first
      end

      def initial_timeline_entry(definition)
        Array(definition[:timelines]).each do |timeline|
          entry = Array(timeline).first
          return entry if entry
        end

        nil
      end

      def initial_scene(definition)
        entry = initial_timeline_entry(definition)
        scene_name = entry&.dig(:scene)
        return first_scene(definition) unless scene_name

        Array(definition[:scenes]).find do |candidate|
          candidate[:name].to_s == scene_name.to_s
        end
      end

      def fallback_scene
        scene_file = active_scene_file
        scene_name = scene_file ? scene_file.basename(".rb").to_s : ""

        {
          name: scene_name.empty? ? DEFAULT_PROFILE_NAME.to_sym : scene_name.to_sym,
          layers: []
        }
      end

      def start_midi_runtime(definition, broadcaster)
        settings = midi_runtime_settings(definition)
        return nil unless settings[:enabled]

        midi_input = Vizcore::Audio::MidiInput.new(device: settings[:device])
        executor = Vizcore::DSL::MidiMapExecutor.new(
          midi_maps: settings[:midi_maps],
          scenes: settings[:scenes],
          globals: settings[:globals]
        )
        midi_input.start { |event| handle_midi_event(executor, event, broadcaster) }
        @output.puts("MIDI mapping enabled#{settings[:device] ? " (device=#{settings[:device]})" : ""}")

        {
          input: midi_input,
          executor: executor,
          device: settings[:device]
        }
      rescue StandardError => e
        @output.puts(Vizcore::ErrorFormatting.summarize(e, context: "MIDI runtime disabled"))
        midi_input&.stop
        nil
      end

      def refresh_midi_runtime(runtime, definition, broadcaster)
        settings = midi_runtime_settings(definition)
        return stop_midi_runtime(runtime) unless settings[:enabled]
        return start_midi_runtime(definition, broadcaster) unless runtime

        if runtime[:device] != settings[:device]
          stop_midi_runtime(runtime)
          return start_midi_runtime(definition, broadcaster)
        end

        runtime[:executor].update(
          midi_maps: settings[:midi_maps],
          scenes: settings[:scenes],
          globals: settings[:globals]
        )
        runtime
      rescue StandardError => e
        @output.puts(Vizcore::ErrorFormatting.summarize(e, context: "MIDI runtime update failed"))
        runtime
      end

      def stop_midi_runtime(runtime)
        return nil unless runtime

        runtime[:input]&.stop
        nil
      rescue StandardError => e
        @output.puts(Vizcore::ErrorFormatting.summarize(e, context: "MIDI runtime shutdown failed"))
        nil
      end

      def start_osc_runtime(broadcaster)
        return nil unless @config.osc_port

        @osc_runtime_active = true
        receiver = Vizcore::Sync::OscReceiver.new(
          host: @config.host,
          port: @config.osc_port,
          handler: ->(message) { handle_osc_messages(message, broadcaster) },
          error_reporter: ->(message) { @output.puts(message) }
        )
        receiver.start
      rescue StandardError => e
        @output.puts(Vizcore::ErrorFormatting.summarize(e, context: "OSC runtime disabled"))
        receiver&.stop
        @osc_runtime_active = false
        nil
      end

      def stop_osc_runtime(runtime)
        @osc_runtime_active = false
        clear_scheduled_osc_messages
        runtime&.stop
        nil
      rescue StandardError => e
        @output.puts(Vizcore::ErrorFormatting.summarize(e, context: "OSC runtime shutdown failed"))
        nil
      end

      def handle_osc_messages(messages, broadcaster)
        Array(messages).each do |message|
          next unless message
          handle_osc_message(message, broadcaster)
        end
      end

      def handle_osc_message(message, broadcaster)
        return unless @osc_runtime_active

        target_time = finite_float(message.timetag)
        return process_osc_message(message, broadcaster) if target_time.nil?

        delay = target_time - wall_clock_seconds
        return process_osc_message(message, broadcaster) if delay <= 0

        schedule_osc_message(message, broadcaster, delay)
      rescue StandardError => e
        @output.puts(Vizcore::ErrorFormatting.summarize(e, context: "OSC control message failed"))
      end

      def schedule_osc_message(message, broadcaster, delay)
        thread = Thread.new do
          sleep(delay)
          return unless @osc_runtime_active

          process_osc_message(message, broadcaster)
        ensure
          @osc_schedule_mutex.synchronize { @osc_schedule_threads.delete(Thread.current) }
        end
        @osc_schedule_mutex.synchronize { @osc_schedule_threads << thread }
      end

      def clear_scheduled_osc_messages
        threads = @osc_schedule_mutex.synchronize do
          threads = Array(@osc_schedule_threads)
          @osc_schedule_threads.clear
          threads
        end
        threads.each do |thread|
          thread.kill
          thread.join(0.05)
        rescue StandardError
          nil
        end
      end

      def process_osc_message(message, broadcaster)
        case message.address
        when "/vizcore/scene"
          arguments = Array(message.arguments)
          target_name = arguments.first
          effect = parse_osc_scene_effect(arguments.drop(1))
          switch_scene_from_client(target_name, broadcaster, source: "osc", effect: effect)
        when "/vizcore/tap"
          apply_tap_tempo({ "client_tapped_at_ms" => wall_clock_ms }, broadcaster)
        when "/vizcore/bpm"
          apply_osc_bpm(message.arguments.first, broadcaster)
        when "/vizcore/bpm_unlock"
          apply_osc_bpm_unlock(broadcaster)
        when %r{\A/vizcore/global/([^/]+)\z}
          apply_osc_global(Regexp.last_match(1), message.arguments)
        when %r{\A/vizcore/layer/([^/]+)/(.+)\z}
          apply_osc_layer_param(broadcaster, Regexp.last_match(1), Regexp.last_match(2), message.arguments)
        when %r{\A/vizcore/live/(blackout|freeze)\z}
          apply_osc_live_control(Regexp.last_match(1), message.arguments)
        when "/vizcore/transport/play", "/vizcore/transport/position"
          apply_osc_transport(broadcaster, playing: true, position_seconds: message.arguments.first)
        when "/vizcore/transport/stop"
          apply_osc_transport(broadcaster, playing: false, position_seconds: message.arguments.first)
        end
      end

      def handle_midi_event(executor, event, broadcaster)
        actions = executor.handle_event(event)
        actions.each do |action|
          apply_midi_action(action, executor, broadcaster)
        end
      rescue StandardError => e
        @output.puts(Vizcore::ErrorFormatting.summarize(e, context: "MIDI action failed"))
      end

      def register_client_message_handler(broadcaster)
        Vizcore::Server::WebSocketHandler.on_message do |message, socket|
          handle_client_message(message, broadcaster, socket)
        end
      end

      def switch_profile(raw_profile, broadcaster)
        profile = normalize_profile_name(raw_profile)
        return if profile == active_profile_for_api

        unless available_profiles_for_api.include?(profile)
          WebSocketHandler.broadcast(
            type: "runtime_error",
            payload: {
              source: "profile",
              context: "Unknown profile: #{profile}",
              event: "unknown_profile",
              message: "Profile not found: #{profile}"
            }
          )
          return
        end

        scene_file = active_scene_file_for_profile(profile)
        if scene_file.nil? || !scene_file.file?
          WebSocketHandler.broadcast(
            type: "runtime_error",
            payload: {
              source: "profile",
              context: "Profile scene file missing",
              event: "profile_scene_missing",
              message: "Missing scene file for profile: #{profile}"
            }
          )
          return
        end

        definition = load_definition_for_profile(profile)
        scene = configure_runtime_for_definition(definition: definition, broadcaster: broadcaster)
        @midi_runtime = refresh_midi_runtime(@midi_runtime, definition, broadcaster)
        restart_scene_watcher_for_profile(profile_scene_file: scene_file, definition: definition, broadcaster: broadcaster)
        @active_profile = profile
        @active_scene_file = scene_file
        broadcast_config_update(scene: scene, definition: definition)
      rescue StandardError => e
        message = Vizcore::ErrorFormatting.summarize(e, context: "Profile switch failed")
        @output.puts(message)
        WebSocketHandler.broadcast(
          type: "runtime_error",
          payload: {
            source: "profile",
            context: "Profile switch failed",
            event: "profile_switch_failed",
            message: message
          }
        )
      end

      def restart_scene_watcher_for_profile(profile_scene_file:, definition:, broadcaster:)
        return unless @config.reload?

        new_watcher = start_scene_watcher(
          broadcaster,
          definition: definition,
          scene_file: profile_scene_file
        )
        return unless new_watcher

        old_watcher = @scene_watcher
        @scene_watcher = new_watcher
        old_watcher&.stop
      end

      def handle_client_message(message, broadcaster, socket = nil)
        type = message["type"] || message[:type]
        payload = message["payload"] || message[:payload]
        case type.to_s
        when "latency_probe"
          respond_to_latency_probe(socket, payload)
        when "transport_sync"
          return unless file_transport_enabled?

          values = Hash(payload)
          playing = values.fetch("playing", values.fetch(:playing, false))
          return unless client_transport_sync_allowed?(socket, playing: playing)

          broadcaster.sync_transport(
            playing: playing,
            position_seconds: values.fetch("position_seconds", values.fetch(:position_seconds, 0.0))
          )
        when "switch_scene"
          values = Hash(payload)
          target_name = values.fetch("scene", values.fetch(:scene, values.fetch("scene_name", values.fetch(:scene_name, nil))))
          effect = normalize_transition_effect(values["effect"] || values[:effect])
          switch_scene_from_client(target_name, broadcaster, effect: effect)
        when "switch_profile"
          switch_profile((payload || {})["profile"] || (payload || {})[:profile], broadcaster)
        when "tap_tempo"
          apply_tap_tempo(payload, broadcaster)
        when "custom_shape_param"
          apply_custom_shape_param(payload, broadcaster)
        when "client_runtime_error"
          report_client_runtime_error(payload)
        end
      rescue StandardError => e
        @output.puts(Vizcore::ErrorFormatting.summarize(e, context: "Client control message failed"))
      end

      def respond_to_latency_probe(socket, payload)
        return unless socket

        received_at_ms = wall_clock_ms
        values = Hash(payload)
        response = {
          server_received_at_ms: received_at_ms,
          server_sent_at_ms: wall_clock_ms
        }
        client_sent_at_ms = finite_float(values["client_sent_at_ms"] || values[:client_sent_at_ms])
        response[:client_sent_at_ms] = client_sent_at_ms if client_sent_at_ms

        WebSocketHandler.send_to(socket, type: "latency_probe", payload: response)
      end

      def client_transport_sync_allowed?(socket, playing:)
        return true unless socket

        role = WebSocketHandler.role_for(socket)
        return true if role == WebSocketHandler::CONTROL_ROLE

        !!playing
      end

      def report_client_runtime_error(payload)
        values = Hash(payload)
        message = values["message"] || values[:message]
        return unless message

        context = values["context"] || values[:context] || "Client runtime error"
        source = normalize_client_error_source(values["source"] || values[:source])
        event = values["event"] || values[:event]
        WebSocketHandler.broadcast(
          type: "runtime_error",
          payload: {
            source: source,
            context: String(context),
            message: String(message),
            frame_id: current_frame_id(values),
            event: event
          }
        )
      end

      def current_frame_id(values)
        frame_id = values["frame_id"] || values[:frame_id]
        parsed = finite_float(frame_id)
        parsed if parsed
      rescue StandardError
        nil
      end

      def normalize_client_error_source(value)
        source = String(value || "runtime").strip
        source.empty? ? "runtime" : source
      end

      def apply_midi_action(action, executor, broadcaster)
        case action[:type]
        when :switch_scene
          target_scene = action[:scene]
          return unless target_scene

          apply_midi_scene_change(target_scene, action[:effect], broadcaster)
        when :next_scene
          target_scene = adjacent_scene_for(broadcaster.current_scene_snapshot[:name], offset: 1)
          apply_midi_scene_change(target_scene, action[:effect], broadcaster) if target_scene
        when :previous_scene
          target_scene = adjacent_scene_for(broadcaster.current_scene_snapshot[:name], offset: -1)
          apply_midi_scene_change(target_scene, action[:effect], broadcaster) if target_scene
        when :set_global
          WebSocketHandler.broadcast(
            type: "config_update",
            payload: {
              globals: executor.globals
            }
          )
        when :live_control
          apply_midi_live_control(action[:control], action)
        end
      end

      def apply_midi_live_control(control, action)
        control_name = control.to_s
        return unless @live_controls.key?(control_name)

        @live_controls[control_name] = normalize_live_control_state(action)
        WebSocketHandler.broadcast(
          type: "config_update",
          payload: {
            live_controls: @live_controls.dup,
            source: "midi"
          }
        )
      end

      def apply_midi_scene_change(target_scene, effect, broadcaster)
        current = broadcaster.current_scene_snapshot
        from_scene = current[:name]
        broadcaster.update_scene(scene_name: target_scene[:name], scene_layers: target_scene[:layers])
        WebSocketHandler.broadcast(
          type: "scene_change",
          payload: {
            from: from_scene.to_s,
            to: target_scene[:name].to_s,
            effect: effect,
            source: "midi"
          }
        )
      end

      def midi_runtime_settings(definition)
        midi_inputs = Array(definition[:midi])

        {
          enabled: !Array(definition[:midi_maps]).empty?,
          midi_maps: Array(definition[:midi_maps]),
          scenes: Array(definition[:scenes]),
          globals: globals_for(definition),
          device: midi_inputs.first&.dig(:options, :device)
        }
      end

      def globals_for(definition)
        Hash(definition[:globals] || {})
      rescue StandardError
        {}
      end

      def replace_runtime_globals(values)
        @runtime_globals_mutex.synchronize do
          @runtime_globals = normalize_runtime_globals(values)
        end
      end

      def set_runtime_global(name, value)
        key = name.to_s.strip
        return runtime_globals_snapshot if key.empty?

        @runtime_globals_mutex.synchronize do
          @runtime_globals[key] = value
          @runtime_globals.dup
        end
      end

      def runtime_globals_snapshot
        @runtime_globals_mutex.synchronize { @runtime_globals.dup }
      end

      def normalize_runtime_globals(values)
        Hash(values || {}).each_with_object({}) do |(key, value), output|
          name = key.to_s.strip
          output[name] = value unless name.empty?
        end
      rescue StandardError
        {}
      end

      def key_mappings_for(definition)
        Array(definition[:key_mappings]).map do |mapping|
          key = mapping[:key] || mapping["key"]
          action = mapping[:action] || mapping["action"]
          {
            key: key.to_s,
            action: action
          }
        end
      rescue StandardError
        []
      end

      def resolve_shader_sources(definition, scene_file: nil)
        @shader_source_resolver.resolve(
          definition: definition,
          scene_file: (scene_file || active_scene_file).to_s
        )
      end

      def replace_scene_catalog(scenes)
        @scene_catalog_mutex.synchronize do
          @scene_catalog = Array(scenes)
        end
      end

      def scene_names_for(definition)
        Array(definition[:scenes]).filter_map do |scene|
          name = scene.dig(:name) || scene["name"]
          next if name.nil?

          value = name.to_s.strip
          next if value.empty?

          value
        end
      rescue StandardError
        []
      end

      def audio_normalize_settings(definition)
        Hash(definition[:analysis] || {})[:audio_normalize]
      rescue StandardError
        nil
      end

      def analysis_setting(definition, key, fallback)
        Hash(definition[:analysis] || {}).fetch(key, fallback)
      rescue StandardError
        fallback
      end

      def bpm_setting(definition)
        @config.bpm || Hash(definition[:analysis] || {})[:bpm]
      rescue StandardError
        @config.bpm
      end

      def bpm_lock_setting(definition)
        @config.bpm_lock? || !!Hash(definition[:analysis] || {})[:bpm_lock]
      rescue StandardError
        @config.bpm_lock?
      end

      def tap_tempo_key(definition)
        settings = Hash(definition.dig(:analysis, :tap_tempo) || {})
        key = settings[:key] || settings["key"]
        key.to_s unless key.nil? || key.to_s.empty?
      rescue StandardError
        nil
      end

      def apply_tap_tempo(payload, broadcaster)
        return unless @tap_tempo_key

        values = Hash(payload)
        tapped_at_ms = finite_float(values["client_tapped_at_ms"] || values[:client_tapped_at_ms]) || wall_clock_ms
        bpm = broadcaster.tap_tempo(timestamp_ms: tapped_at_ms)
        return unless bpm

        WebSocketHandler.broadcast(
          type: "config_update",
          payload: {
            bpm: bpm,
            bpm_lock: true,
            source: "tap_tempo"
          }
        )
      end

      def apply_osc_bpm(value, broadcaster)
        bpm = finite_float(value)
        return unless bpm&.positive?
        return unless broadcaster.respond_to?(:lock_bpm)

        locked_bpm = broadcaster.lock_bpm(bpm)
        return unless locked_bpm

        WebSocketHandler.broadcast(
          type: "config_update",
          payload: {
            bpm: locked_bpm,
            bpm_lock: true,
            source: "osc"
          }
        )
      end

      def apply_osc_bpm_unlock(broadcaster)
        return unless broadcaster.respond_to?(:unlock_bpm)

        broadcaster.unlock_bpm
        WebSocketHandler.broadcast(
          type: "config_update",
          payload: {
            bpm_lock: false,
            source: "osc"
          }
        )
      end

      def apply_osc_global(name, arguments)
        globals = set_runtime_global(name, normalize_osc_argument(arguments))
        WebSocketHandler.broadcast(
          type: "config_update",
          payload: {
            globals: globals,
            source: "osc"
          }
        )
      end

      def apply_osc_layer_param(broadcaster, layer_name, param, arguments)
        return unless broadcaster.respond_to?(:set_layer_param)

        overrides = broadcaster.set_layer_param(
          layer_name: layer_name,
          param: param.to_s.tr("/", "."),
          value: normalize_osc_argument(arguments)
        )
        WebSocketHandler.broadcast(
          type: "config_update",
          payload: {
            layer_params: overrides,
            source: "osc"
          }
        )
      end

      def apply_custom_shape_param(payload, broadcaster)
        return unless broadcaster.respond_to?(:set_custom_shape_param)

        values = Hash(payload)
        overrides = broadcaster.set_custom_shape_param(
          layer_name: values["layer"] || values[:layer] || values["layer_name"] || values[:layer_name],
          custom_shape_index: values["custom_shape_index"] || values[:custom_shape_index] || values["index"] || values[:index],
          param: values["param"] || values[:param],
          value: values["value"] || values[:value]
        )
        WebSocketHandler.broadcast(
          type: "config_update",
          payload: {
            custom_shape_params: overrides,
            source: "ui"
          }
        )
      end

      def apply_osc_live_control(control, value)
        values = Array(value)
        @live_controls[control] = default_live_control_state(
          enabled: osc_truthy?(values.first),
          fade: values[1],
          release: values[2],
          color: values[3]
        )
        WebSocketHandler.broadcast(
          type: "config_update",
          payload: {
            live_controls: @live_controls.dup,
            source: "osc"
          }
        )
      end

      def apply_osc_transport(broadcaster, playing:, position_seconds:)
        return unless file_transport_enabled?

        broadcaster.sync_transport(
          playing: playing,
          position_seconds: finite_float(position_seconds) || 0.0
        )
      end

      def normalize_osc_argument(arguments)
        values = Array(arguments)
        normalize_osc_value(values.first, input_min: values[1], input_max: values[2])
      end

      def normalize_osc_value(value, input_min: nil, input_max: nil)
        numeric = finite_float(value)
        normalized_range = parse_osc_range(input_min, input_max)
        normalized = normalize_osc_range(numeric, input_min: normalized_range[:min], input_max: normalized_range[:max]) unless numeric.nil? || normalized_range.nil?
        return normalized unless normalized.nil?

        numeric.nil? ? value : numeric
      end

      def parse_osc_range(input_min, input_max)
        if input_max.nil?
          return parse_osc_range_preset(input_min) if input_min
          return nil
        end

        {
          min: input_min,
          max: input_max
        }
      end

      def parse_osc_range_preset(value)
        return nil unless value

        symbol = value.to_s.strip.downcase
        case symbol
        when "0..1", "01", "unit", "unit01", "unit_01", "unit_0_1", "normalized"
          { min: 0.0, max: 1.0 }
        when "-1..1", "bipolar", "bip", "minus1..1", "minus1_1", "-1_1", "-1,1", "-1 to 1"
          { min: -1.0, max: 1.0 }
        when "midi", "midicc", "cc", "midi_cc", "0..127", "0..128", "127"
          { min: 0.0, max: 127.0 }
        else
          parse_range_expression(value)
        end
      end

      def parse_range_expression(value)
        text = value.to_s.strip
        from, to = text.split("..", 2)
        return nil if to.nil?

        min = finite_float(from)
        max = finite_float(to)
        return nil if min.nil? || max.nil?

        {
          min: min,
          max: max
        }
      end

      def normalize_osc_range(value, input_min:, input_max:)
        return nil if input_min.nil? || input_max.nil?

        min = finite_float(input_min)
        max = finite_float(input_max)
        return nil if min.nil? || max.nil? || min == max

        ((value - min) / (max - min)).clamp(0.0, 1.0)
      end

      def osc_truthy?(value)
        return true if value.nil?
        return value if value == true || value == false

        numeric = finite_float(value)
        return numeric.positive? unless numeric.nil?

        %w[true on yes 1].include?(value.to_s.strip.downcase)
      end

      def default_live_control_state(enabled: false, fade: nil, release: nil, color: nil)
        {
          "enabled" => !!enabled,
          "fade" => finite_float(fade),
          "release" => finite_float(release),
          "color" => normalize_control_color(color)
        }.compact
      end

      def normalize_live_control_state(value)
        return default_live_control_state(enabled: !!value) unless value.is_a?(Hash)

        values = value.each_with_object({}) do |(entry_key, entry_value), output|
          output[entry_key.to_s] = entry_value
        end
        default_live_control_state(
          enabled: values.fetch("value", values.fetch("enabled", false)),
          fade: values["fade"],
          release: values["release"],
          color: values["color"]
        )
      end

      def switch_scene_from_client(target_name, broadcaster, source: "ui", effect: nil)
        requested = target_name.to_s.strip
        return if requested.empty?

        target_scene = find_scene_catalog_scene(requested)
        return unless target_scene

        current = broadcaster.current_scene_snapshot
        from_scene = current[:name]
        broadcaster.update_scene(scene_name: target_scene[:name], scene_layers: target_scene[:layers])
        resolved_effect = resolve_manual_scene_effect(effect)
        WebSocketHandler.broadcast(
          type: "scene_change",
          payload: {
            from: from_scene.to_s,
            to: target_scene[:name].to_s,
            effect: resolved_effect,
            source: source
          }
        )
      end

      def resolve_manual_scene_effect(effect)
        normalized = normalize_transition_effect(effect)
        return normalized unless normalized.nil?
        return nil unless @config.respond_to?(:scene_switch_effect)

        deep_dup(@config.scene_switch_effect)
      rescue StandardError
        nil
      end

      def normalize_transition_effect(value)
        return nil unless value
        return nil if value.is_a?(Array)
        return value unless value.is_a?(Hash)

        if value[:name] || value["name"]
          {
            name: value[:name] || value["name"],
            options: value[:options] || value["options"] || {}
          }
        else
          value
        end
      rescue StandardError
        nil
      end

      def parse_osc_scene_effect(arguments)
        return nil if arguments.empty?

        name = arguments[0]
        return nil unless name

        effect_name = name.to_s.strip
        return nil if effect_name.empty?

        duration = finite_float(arguments[1])
        return { name: effect_name.to_sym } if duration.nil?

        { name: effect_name.to_sym, options: { duration: duration } }
      rescue StandardError
        nil
      end

      def deep_dup(value)
        Vizcore::DeepCopy.copy(value)
      end

      def find_scene_catalog_scene(name)
        @scene_catalog_mutex.synchronize do
          Array(@scene_catalog).each do |scene|
            raw_name = scene.dig(:name) || scene["name"]
            next unless raw_name
            next unless raw_name.to_s == name

            layers = scene.dig(:layers) || scene["layers"]
            return { name: raw_name.to_sym, layers: Array(layers) }
          end
          nil
        end
      rescue StandardError
        nil
      end

      def adjacent_scene_for(current_name, offset:)
        @scene_catalog_mutex.synchronize do
          scenes = Array(@scene_catalog)
          return nil if scenes.empty?

          current_index = scenes.index do |scene|
            raw_name = scene.dig(:name) || scene["name"]
            raw_name.to_s == current_name.to_s
          end
          return nil unless current_index

          target = scenes[(current_index + Integer(offset)) % scenes.length]
          raw_name = target.dig(:name) || target["name"]
          layers = target.dig(:layers) || target["layers"]
          { name: raw_name.to_sym, layers: Array(layers) }
        end
      rescue StandardError
        nil
      end

      def wall_clock_ms
        wall_clock_seconds * 1000.0
      end

      def wall_clock_seconds
        Time.now.to_f
      end

      def finite_float(value)
        numeric = Float(value)
        return nil unless numeric.finite?

        numeric
      rescue StandardError
        nil
      end

      def normalize_control_color(value)
        return nil if value.nil?

        if value.is_a?(Array)
          return nil unless (3..4).cover?(value.length)

          channels = Array(value).map { |entry| Float(entry, exception: false) }
          return nil if channels.include?(nil)

          rgb = channels.take(3)
          alpha = channels[3]
          normalized_rgb = if rgb.all? { |channel| channel.between?(0.0, 1.0) }
            rgb
          else
            rgb.map { |channel| channel / 255.0 }
          end
          normalized = normalized_rgb.map { |channel| [0.0, [1.0, channel].min].max }
          return alpha.nil? ? normalized : normalized + [normalize_control_alpha(alpha)]
        end

        raw = value.to_s.strip
        match = raw.match(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/)
        return nil unless match

        raw_hex = match[1]
        hex = raw_hex.length == 3 || raw_hex.length == 4 ? raw_hex.chars.map { |entry| "#{entry}#{entry}" }.join("") : raw_hex

        [
          Integer("0x#{hex[0, 2]}", 16),
          Integer("0x#{hex[2, 2]}", 16),
          Integer("0x#{hex[4, 2]}", 16),
          Integer("0x#{hex[6, 2]}", 16)
        ].take(raw_hex.length > 4 ? 4 : 3).map { |channel| [0.0, [1.0, channel / 255.0].min].max }
      rescue StandardError
        nil
      end

      def normalize_control_alpha(value)
        return nil if value.nil?

        alpha = Float(value, exception: false)
        return nil if alpha.nil?
        return [0.0, [1.0, alpha].min].max if alpha.between?(0.0, 1.0)

        [0.0, [1.0, alpha / 255.0].min].max
      end
    end
  end
end
