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
      # @param config [Vizcore::Config]
      # @param output [#puts]
      def initialize(config, output: $stdout)
        @config = config
        @output = output
        @shader_source_resolver = Vizcore::DSL::ShaderSourceResolver.new
        @scene_catalog_mutex = Mutex.new
        @scene_catalog = []
      end

      # Run server lifecycle until interrupted.
      #
      # @raise [Vizcore::ConfigurationError]
      # @raise [Vizcore::SceneLoadError]
      # @return [void]
      def run
        validate_scene_file!
        validate_feature_settings!
        validate_control_preset_settings!
        validate_plugin_asset_settings!
        validate_audio_settings!
        definition = load_definition!
        control_preset = load_control_preset
        @tap_tempo_key = tap_tempo_key(definition)
        scene = first_scene(definition) || fallback_scene

        app = RackApp.new(
          frontend_root: Vizcore.frontend_root,
          audio_source: runtime_audio_source,
          audio_file: runtime_audio_file,
          scene_names: scene_names_for(definition),
          tap_tempo_key: @tap_tempo_key,
          key_mappings: key_mappings_for(definition),
          globals: globals_for(definition),
          control_preset: control_preset,
          plugin_assets: @config.plugin_assets,
          projector_mode: @config.projector_mode
        )
        server = Puma::Server.new(app, nil, min_threads: 0, max_threads: 4)
        server.add_tcp_listener(@config.host, @config.port)
        server.run

        input_manager = build_input_manager
        broadcaster = FrameBroadcaster.new(
          scene_name: scene[:name].to_s,
          scene_layers: scene[:layers],
          scene_catalog: definition[:scenes],
          transitions: definition[:transitions],
          input_manager: input_manager,
          analysis_pipeline: replay_pipeline,
          noise_gate: @config.noise_gate,
          audio_normalize: audio_normalize_settings(definition),
          bpm: bpm_setting(definition),
          bpm_lock: bpm_lock_setting(definition),
          error_reporter: ->(message) { @output.puts(message) }
        )
        replace_scene_catalog(definition[:scenes])
        if file_transport_enabled?
          broadcaster.sync_transport(playing: false, position_seconds: 0.0)
        end
        broadcaster.start
        register_client_message_handler(broadcaster)
        midi_runtime = start_midi_runtime(definition, broadcaster)
        osc_runtime = start_osc_runtime(broadcaster)
        watcher = if @config.reload?
                    start_scene_watcher(broadcaster, definition: definition) do |updated_definition|
                      midi_runtime = refresh_midi_runtime(midi_runtime, updated_definition, broadcaster)
                    end
                  end

        @output.puts("Vizcore server listening at http://#{@config.host}:#{@config.port}")
        @output.puts("Projector output: http://#{@config.host}:#{@config.port}/projector")
        @output.puts("Control panel: http://#{@config.host}:#{@config.port}/control")
        @output.puts("Scene: #{scene[:name]}")
        @output.puts("Hot reload: #{@config.reload? ? 'enabled' : 'disabled'}")
        @output.puts("Audio playback: http://#{@config.host}:#{@config.port}/audio-file") if file_transport_enabled?
        @output.puts("Feature replay: #{@config.feature_file}") if feature_replay?
        @output.puts("OSC sync: udp://#{@config.host}:#{@config.osc_port}") if osc_runtime
        @output.puts("Press Ctrl+C to stop.")

        wait_for_interrupt
      ensure
        Vizcore::Server::WebSocketHandler.clear_message_handler
        stop_osc_runtime(osc_runtime)
        stop_midi_runtime(midi_runtime)
        watcher&.stop
        broadcaster&.stop
        server&.stop(true)
      end

      private

      def validate_scene_file!
        return if @config.scene_exists?

        message = if @config.scene_file
                    "Scene file not found: #{@config.scene_file}"
                  else
                    "Scene file is required"
                  end

        raise Vizcore::ConfigurationError, message
      end

      def load_definition!
        raw_definition = Vizcore::DSL::Engine.load_file(@config.scene_file.to_s)
        resolve_shader_sources(raw_definition)
      rescue StandardError => e
        raise Vizcore::SceneLoadError, Vizcore::ErrorFormatting.summarize(
          e,
          context: "Failed to load scene file #{@config.scene_file}"
        )
      end

      def validate_audio_settings!
        return if feature_replay?
        return unless @config.audio_source == :file
        return if @config.audio_file && @config.audio_file.file?

        raise Vizcore::ConfigurationError, "Audio file not found: #{@config.audio_file || '(nil)'}"
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

      def wait_for_interrupt
        stop_requested = false
        %w[INT TERM].each do |signal_name|
          Signal.trap(signal_name) { stop_requested = true }
        rescue ArgumentError
          nil
        end
        sleep(0.1) until stop_requested
      end

      def start_scene_watcher(broadcaster, definition:, &on_reload)
        watcher = Vizcore::Server::SceneDependencyWatcher.new(scene_file: @config.scene_file.to_s, definition: definition) do |definition, _changed_path|
          definition = resolve_shader_sources(definition)
          replace_scene_catalog(definition[:scenes])
          @tap_tempo_key = tap_tempo_key(definition)
          scene = first_scene(definition) || fallback_scene
          broadcaster.update_transition_definition(
            scenes: Array(definition[:scenes]),
            transitions: Array(definition[:transitions])
          )
          broadcaster.update_analysis_settings(
            audio_normalize: audio_normalize_settings(definition),
            bpm: bpm_setting(definition),
            bpm_lock: bpm_lock_setting(definition)
          )
          broadcaster.update_scene(scene_name: scene[:name], scene_layers: scene[:layers])
          on_reload&.call(definition)
          WebSocketHandler.broadcast(
            type: "config_update",
            payload: {
              scene: scene,
              scenes: scene_names_for(definition),
              tap_tempo_key: @tap_tempo_key,
              key_mappings: key_mappings_for(definition),
              globals: globals_for(definition)
            }
          )
          @output.puts("Scene reloaded: #{scene[:name]}")
        rescue StandardError => e
          @output.puts(Vizcore::ErrorFormatting.summarize(e, context: "Scene reload failed"))
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

      def fallback_scene
        {
          name: @config.scene_file.basename(".rb").to_sym,
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

        receiver = Vizcore::Sync::OscReceiver.new(
          host: @config.host,
          port: @config.osc_port,
          handler: ->(message) { handle_osc_message(message, broadcaster) },
          error_reporter: ->(message) { @output.puts(message) }
        )
        receiver.start
      rescue StandardError => e
        @output.puts(Vizcore::ErrorFormatting.summarize(e, context: "OSC runtime disabled"))
        receiver&.stop
        nil
      end

      def stop_osc_runtime(runtime)
        runtime&.stop
        nil
      rescue StandardError => e
        @output.puts(Vizcore::ErrorFormatting.summarize(e, context: "OSC runtime shutdown failed"))
        nil
      end

      def handle_osc_message(message, broadcaster)
        case message.address
        when "/vizcore/scene"
          switch_scene_from_client(message.arguments.first, broadcaster, source: "osc")
        when "/vizcore/tap"
          apply_tap_tempo({ "client_tapped_at_ms" => wall_clock_ms }, broadcaster)
        end
      rescue StandardError => e
        @output.puts(Vizcore::ErrorFormatting.summarize(e, context: "OSC control message failed"))
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

      def handle_client_message(message, broadcaster, socket = nil)
        type = message["type"] || message[:type]
        payload = message["payload"] || message[:payload]
        case type.to_s
        when "latency_probe"
          respond_to_latency_probe(socket, payload)
        when "transport_sync"
          return unless file_transport_enabled?

          values = Hash(payload)
          broadcaster.sync_transport(
            playing: values.fetch("playing", values.fetch(:playing, false)),
            position_seconds: values.fetch("position_seconds", values.fetch(:position_seconds, 0.0))
          )
        when "switch_scene"
          values = Hash(payload)
          target_name = values.fetch("scene", values.fetch(:scene, values.fetch("scene_name", values.fetch(:scene_name, nil))))
          switch_scene_from_client(target_name, broadcaster)
        when "tap_tempo"
          apply_tap_tempo(payload, broadcaster)
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

      def apply_midi_action(action, executor, broadcaster)
        case action[:type]
        when :switch_scene
          target_scene = action[:scene]
          return unless target_scene

          current = broadcaster.current_scene_snapshot
          from_scene = current[:name]
          broadcaster.update_scene(scene_name: target_scene[:name], scene_layers: target_scene[:layers])
          WebSocketHandler.broadcast(
            type: "scene_change",
            payload: {
              from: from_scene.to_s,
              to: target_scene[:name].to_s,
              effect: action[:effect],
              source: "midi"
            }
          )
        when :set_global
          WebSocketHandler.broadcast(
            type: "config_update",
            payload: {
              globals: executor.globals
            }
          )
        end
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

      def resolve_shader_sources(definition)
        @shader_source_resolver.resolve(definition: definition, scene_file: @config.scene_file.to_s)
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

      def switch_scene_from_client(target_name, broadcaster, source: "ui")
        requested = target_name.to_s.strip
        return if requested.empty?

        target_scene = find_scene_catalog_scene(requested)
        return unless target_scene

        current = broadcaster.current_scene_snapshot
        from_scene = current[:name]
        broadcaster.update_scene(scene_name: target_scene[:name], scene_layers: target_scene[:layers])
        WebSocketHandler.broadcast(
          type: "scene_change",
          payload: {
            from: from_scene.to_s,
            to: target_scene[:name].to_s,
            effect: nil,
            source: source
          }
        )
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

      def wall_clock_ms
        Time.now.to_f * 1000.0
      end

      def finite_float(value)
        numeric = Float(value)
        return nil unless numeric.finite?

        numeric
      rescue StandardError
        nil
      end
    end
  end
end
