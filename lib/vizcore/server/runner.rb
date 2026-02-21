# frozen_string_literal: true

require "puma"
require_relative "../config"
require_relative "../dsl"
require_relative "frame_broadcaster"
require_relative "rack_app"
require_relative "websocket_handler"

module Vizcore
  module Server
    class Runner
      def initialize(config, output: $stdout)
        @config = config
        @output = output
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
          input_manager: input_manager
        )
        broadcaster.start
        watcher = start_scene_watcher(broadcaster)

        @output.puts("Vizcore server listening at http://#{@config.host}:#{@config.port}")
        @output.puts("Scene: #{scene[:name]}")
        @output.puts("Press Ctrl+C to stop.")

        wait_for_interrupt
      ensure
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

        raise ArgumentError, message
      end

      def load_definition!
        Vizcore::DSL::Engine.load_file(@config.scene_file.to_s)
      rescue StandardError => e
        raise ArgumentError, "Failed to load scene file: #{e.message}"
      end

      def validate_audio_settings!
        return unless @config.audio_source == :file
        return if @config.audio_file && @config.audio_file.file?

        raise ArgumentError, "Audio file not found: #{@config.audio_file || '(nil)'}"
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

      def start_scene_watcher(broadcaster)
        watcher = Vizcore::DSL::Engine.watch_file(@config.scene_file.to_s) do |definition, _changed_path|
          scene = first_scene(definition) || fallback_scene
          broadcaster.update_transition_definition(
            scenes: Array(definition[:scenes]),
            transitions: Array(definition[:transitions])
          )
          broadcaster.update_scene(scene_name: scene[:name], scene_layers: scene[:layers])
          WebSocketHandler.broadcast(type: "config_update", payload: { scene: scene })
          @output.puts("Scene reloaded: #{scene[:name]}")
        rescue StandardError => e
          @output.puts("Scene reload failed: #{e.message}")
        end
        watcher.start
        watcher
      rescue StandardError => e
        @output.puts("Scene watcher disabled: #{e.message}")
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
    end
  end
end
