# frozen_string_literal: true

require "fileutils"
require "pathname"
require "thor"
require_relative "../vizcore"
require_relative "audio"
require_relative "config"
require_relative "server"

module Vizcore
  class CLI < Thor
    package_name "vizcore"

    default_command :help

    desc "start SCENE_FILE", "Start vizcore HTTP/WebSocket server"
    option :host, type: :string, default: Config::DEFAULT_HOST, desc: "Bind host"
    option :port, type: :numeric, default: Config::DEFAULT_PORT, desc: "Bind port"
    option :audio_source, type: :string, default: Config::DEFAULT_AUDIO_SOURCE.to_s, desc: "Audio source: mic, file, dummy"
    option :audio_file, type: :string, desc: "Path to audio file used when --audio-source file (wav/mp3/flac)"
    def start(scene_file)
      config = Config.new(
        scene_file: scene_file,
        host: options.fetch(:host),
        port: options.fetch(:port),
        audio_source: options.fetch(:audio_source),
        audio_file: options[:audio_file]
      )
      Server::Runner.new(config).run
    rescue ArgumentError => e
      raise Thor::Error, e.message
    end

    desc "new NAME", "Create a starter project scaffold"
    def new(name)
      root = Pathname.new(name).expand_path
      FileUtils.mkdir_p(root.join("scenes"))
      FileUtils.mkdir_p(root.join("shaders"))

      write_template("project_readme.md", root.join("README.md"), project_name: name)
      write_template("basic_scene.rb", root.join("scenes", "basic.rb"), project_name: name)

      say("Created project scaffold: #{root}")
      say("Next: cd #{name} && vizcore start scenes/basic.rb")
    end

    desc "devices [TYPE]", "Show available devices (audio or midi)"
    def devices(type = nil)
      case type
      when nil
        print_audio_devices
        print_midi_devices
      when "audio"
        print_audio_devices
      when "midi"
        print_midi_devices
      else
        raise Thor::Error, "Unknown type: #{type}. Use `audio` or `midi`."
      end
    end

    private

    def write_template(template_name, destination, project_name:)
      template_path = Vizcore.templates_root.join(template_name)
      body = template_path.read.gsub("{{project_name}}", project_name)
      destination.write(body)
    end

    def print_audio_devices
      say("Audio devices:")
      Vizcore::Audio::InputManager.available_audio_devices.each do |device|
        index = device[:index]
        name = device[:name]
        channels = device[:max_input_channels]
        sample_rate = device[:default_sample_rate]
        say("  - #{index}: #{name} (inputs=#{channels}, rate=#{sample_rate})")
      end
    end

    def print_midi_devices
      say("MIDI devices:")
      Vizcore::Audio::InputManager.available_midi_devices.each do |device|
        say("  - #{device[:id]}: #{device[:name]}")
      end
    end
  end
end
