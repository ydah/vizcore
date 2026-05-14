# frozen_string_literal: true

require "fileutils"
require "pathname"
require "thor"
require_relative "../vizcore"
require_relative "audio"
require_relative "cli/doctor"
require_relative "cli/scene_diagnostics"
require_relative "config"
require_relative "server"

module Vizcore
  # Thor-based CLI entrypoint for Vizcore.
  class CLI < Thor
    package_name "vizcore"

    # Exit with non-zero status when a Thor command fails.
    #
    # @return [Boolean]
    def self.exit_on_failure?
      true
    end

    default_command :help

    desc "start SCENE_FILE", "Start vizcore HTTP/WebSocket server"
    option :host, type: :string, default: Config::DEFAULT_HOST, desc: "Bind host"
    option :port, type: :numeric, default: Config::DEFAULT_PORT, desc: "Bind port"
    option :audio_source, type: :string, default: Config::DEFAULT_AUDIO_SOURCE.to_s, desc: "Audio source: mic, file, dummy"
    option :audio_file, type: :string, desc: "Path to audio file used when --audio-source file (wav/mp3/flac)"
    option :audio_device, type: :string, desc: "Audio input device index or name used when --audio-source mic"
    option :noise_gate, type: :numeric, default: Config::DEFAULT_NOISE_GATE, desc: "RMS level below which audio is treated as silence"
    # Start the Vizcore server with the given scene file.
    #
    # @param scene_file [String] path to a Ruby scene DSL file
    # @raise [Thor::Error] when CLI arguments are invalid
    # @return [void]
    def start(scene_file)
      config = Config.new(
        scene_file: scene_file,
        host: options.fetch(:host),
        port: options.fetch(:port),
        audio_source: options.fetch(:audio_source),
        audio_file: options[:audio_file],
        audio_device: options[:audio_device],
        noise_gate: options.fetch(:noise_gate)
      )
      Server::Runner.new(config).run
    rescue ArgumentError => e
      raise Thor::Error, e.message
    end

    desc "demo", "Start the bundled audio-reactive demo"
    option :host, type: :string, default: Config::DEFAULT_HOST, desc: "Bind host"
    option :port, type: :numeric, default: Config::DEFAULT_PORT, desc: "Bind port"
    option :noise_gate, type: :numeric, default: Config::DEFAULT_NOISE_GATE, desc: "RMS level below which audio is treated as silence"
    # Start a bundled scene with bundled audio for first-run verification.
    #
    # @return [void]
    def demo
      config = Config.new(
        scene_file: Vizcore.root.join("examples", "rhythm_geometry.rb"),
        host: options.fetch(:host),
        port: options.fetch(:port),
        audio_source: :file,
        audio_file: Vizcore.root.join("examples", "assets", "complex_demo_loop.wav"),
        noise_gate: options.fetch(:noise_gate)
      )
      Server::Runner.new(config).run
    rescue ArgumentError => e
      raise Thor::Error, e.message
    end

    desc "new NAME", "Create a starter project scaffold"
    # Generate a new Vizcore project scaffold.
    #
    # @param name [String] directory name for the new project
    # @return [void]
    def new(name)
      root = Pathname.new(name).expand_path
      FileUtils.mkdir_p(root.join("scenes"))
      FileUtils.mkdir_p(root.join("shaders"))

      write_template("project_readme.md", root.join("README.md"), project_name: name)
      write_template("basic_scene.rb", root.join("scenes", "basic.rb"), project_name: name)
      write_template("intro_drop_scene.rb", root.join("scenes", "intro_drop.rb"), project_name: name)
      write_template("midi_control_scene.rb", root.join("scenes", "midi_control.rb"), project_name: name)
      write_template("custom_shader_scene.rb", root.join("scenes", "custom_shader.rb"), project_name: name)
      write_template("custom_wave.frag", root.join("shaders", "custom_wave.frag"), project_name: name)

      say("Created project scaffold: #{root}")
      say("Next: cd #{name} && vizcore start scenes/basic.rb")
    end

    desc "devices [TYPE]", "Show available devices (audio or midi)"
    # Print audio and/or MIDI devices detected by the runtime.
    #
    # @param type [String, nil] `audio`, `midi`, or nil for both
    # @raise [Thor::Error] when an unknown type is provided
    # @return [void]
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

    desc "doctor", "Check local dependencies and device availability"
    # Print local environment checks for Vizcore runtime dependencies.
    #
    # @raise [Thor::Error] when a required check fails
    # @return [void]
    def doctor
      report = Vizcore::CLISupport::Doctor.new.call
      report.checks.each do |check|
        say("#{status_label(check.status)} #{check.name}: #{check.message}")
      end
      raise Thor::Error, "vizcore doctor found required failures" if report.failure?
    end

    map "inspect" => :inspect_scene
    desc "inspect SCENE_FILE", "Print scenes, layers, mappings, and transitions"
    # Load a scene DSL file and print its runtime structure.
    #
    # @param scene_file [String] path to a Ruby scene DSL file
    # @raise [Thor::Error] when scene loading fails
    # @return [void]
    def inspect_scene(scene_file)
      diagnostics = Vizcore::CLISupport::SceneDiagnostics.new(scene_file: scene_file)
      result = diagnostics.validate
      print_issues(result.issues)
      raise Thor::Error, "scene inspection failed" unless result.definition

      diagnostics.inspect_lines(result.definition).each { |line| say(line) }
    end

    desc "validate SCENE_FILE", "Validate a scene DSL file"
    # Load and validate a scene DSL file without starting the server.
    #
    # @param scene_file [String] path to a Ruby scene DSL file
    # @raise [Thor::Error] when validation fails
    # @return [void]
    def validate(scene_file)
      result = Vizcore::CLISupport::SceneDiagnostics.new(scene_file: scene_file).validate
      print_issues(result.issues)
      raise Thor::Error, "scene validation failed" unless result.valid?

      say("Scene valid: #{scene_file}")
    end

    private

    def status_label(status)
      case status
      when :ok
        "[ok]"
      when :warn
        "[warn]"
      else
        "[fail]"
      end
    end

    def print_issues(issues)
      issues.each do |issue|
        label = issue.error? ? "[error]" : "[warn]"
        say("#{label} #{issue.message}")
      end
    end

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
