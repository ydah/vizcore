# frozen_string_literal: true

require "puma"
require_relative "../config"
require_relative "../dsl"
require_relative "../errors"
require_relative "frame_broadcaster"
require_relative "rack_app"
require_relative "websocket_handler"

module Vizcore
  module Server
    class Runner
      def initialize(config, output: $stdout)
        @config = config
        @output = output
        @shader_source_resolver = Vizcore::DSL::ShaderSourceResolver.new
      end

      def run
        validate_scene_file!
        validate_audio_settings!
        definition = load_definition!
        scene = first_scene(definition) || fallback_scene

        app = RackApp.new(frontend_root: Vizcore.frontend_root)
        server = Puma::Server.new(app, nil, min_threads: 0, max_threads: 4)
        server.add_tcp_listener(@config.host, @config.port)
        server.run

        input_manager = Vizcore::Audio::InputManager.new(
          source: @config.audio_source,
          file_path: @config.audio_file&.to_s
        )
        broadcaster = FrameBroadcaster.new(
          scene_name: scene[:name].to_s,
          scene_layers: scene[:layers],
          scene_catalog: definition[:scenes],
          transitions: definition[:transitions],
          input_manager: input_manager,
          error_reporter: ->(message) { @output.puts(message) }
        )
        broadcaster.start
        midi_runtime = start_midi_runtime(definition, broadcaster)
        watcher = start_scene_watcher(broadcaster) do |updated_definition|
          midi_runtime = refresh_midi_runtime(midi_runtime, updated_definition, broadcaster)
        end

        @output.puts("Vizcore server listening at http://#{@config.host}:#{@config.port}")
        @output.puts("Scene: #{scene[:name]}")
        @output.puts("Press Ctrl+C to stop.")

        wait_for_interrupt
      ensure
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
        return unless @config.audio_source == :file
        return if @config.audio_file && @config.audio_file.file?

        raise Vizcore::ConfigurationError, "Audio file not found: #{@config.audio_file || '(nil)'}"
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

      def start_scene_watcher(broadcaster, &on_reload)
        watcher = Vizcore::DSL::Engine.watch_file(@config.scene_file.to_s) do |definition, _changed_path|
          definition = resolve_shader_sources(definition)
          scene = first_scene(definition) || fallback_scene
          broadcaster.update_transition_definition(
            scenes: Array(definition[:scenes]),
            transitions: Array(definition[:transitions])
          )
          broadcaster.update_scene(scene_name: scene[:name], scene_layers: scene[:layers])
          on_reload&.call(definition)
          WebSocketHandler.broadcast(type: "config_update", payload: { scene: scene })
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

      def handle_midi_event(executor, event, broadcaster)
        actions = executor.handle_event(event)
        actions.each do |action|
          apply_midi_action(action, executor, broadcaster)
        end
      rescue StandardError => e
        @output.puts(Vizcore::ErrorFormatting.summarize(e, context: "MIDI action failed"))
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
          globals: Hash(definition[:globals] || {}),
          device: midi_inputs.first&.dig(:options, :device)
        }
      end

      def resolve_shader_sources(definition)
        @shader_source_resolver.resolve(definition: definition, scene_file: @config.scene_file.to_s)
      end
    end
  end
end
