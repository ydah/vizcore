# frozen_string_literal: true

require "puma"
require_relative "../config"
require_relative "frame_broadcaster"
require_relative "rack_app"

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

        app = RackApp.new(frontend_root: Vizcore.frontend_root)
        server = Puma::Server.new(app, nil, min_threads: 0, max_threads: 4)
        server.add_tcp_listener(@config.host, @config.port)
        server.run

        input_manager = Vizcore::Audio::InputManager.new(
          source: @config.audio_source,
          file_path: @config.audio_file&.to_s
        )
        broadcaster = FrameBroadcaster.new(scene_name: scene_name, input_manager: input_manager)
        broadcaster.start

        @output.puts("Vizcore server listening at http://#{@config.host}:#{@config.port}")
        @output.puts("Scene: #{scene_name}")
        @output.puts("Press Ctrl+C to stop.")

        wait_for_interrupt
      ensure
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

      def scene_name
        @config.scene_file.basename(".rb").to_s
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
    end
  end
end
