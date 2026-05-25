# frozen_string_literal: true

require "fileutils"
require "net/http"
require "pathname"
require "thor"
require_relative "../vizcore"
require_relative "analysis"
require_relative "audio"
require_relative "cli/doctor"
require_relative "cli/dsl_reference"
require_relative "cli/layer_docs"
require_relative "cli/scene_diagnostics"
require_relative "cli/shader_template"
require_relative "cli/shader_uniform_docs"
require_relative "config"
require_relative "project_manifest"
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

    SCAFFOLD_TEMPLATES = {
      "standard" => {
        label: "standard",
        start_scene: "scenes/basic.rb",
        files: [
          ["basic_scene.rb", "scenes/basic.rb", "Minimal wireframe starter"],
          ["intro_drop_scene.rb", "scenes/intro_drop.rb", "Transition flow with beat trigger"],
          ["midi_control_scene.rb", "scenes/midi_control.rb", "MIDI note/CC mapping example"],
          ["custom_shader_scene.rb", "scenes/custom_shader.rb", "Custom GLSL + post/VJ effect example"],
          ["custom_wave.frag", "shaders/custom_wave.frag", "Custom GLSL fragment shader"]
        ],
        notes: [
          "`scenes/custom_shader.rb` references `shaders/custom_wave.frag`.",
          "Use `vizcore devices midi` before running `scenes/midi_control.rb`."
        ]
      },
      "minimal" => {
        label: "minimal",
        start_scene: "scenes/basic.rb",
        files: [
          ["basic_scene.rb", "scenes/basic.rb", "Minimal wireframe starter"]
        ],
        notes: []
      },
      "shader" => {
        label: "shader",
        start_scene: "scenes/custom_shader.rb",
        files: [
          ["custom_shader_scene.rb", "scenes/custom_shader.rb", "Custom GLSL + post/VJ effect example"],
          ["custom_wave.frag", "shaders/custom_wave.frag", "Custom GLSL fragment shader"]
        ],
        notes: [
          "`scenes/custom_shader.rb` references `shaders/custom_wave.frag`."
        ]
      },
      "midi" => {
        label: "midi",
        start_scene: "scenes/midi_control.rb",
        files: [
          ["midi_control_scene.rb", "scenes/midi_control.rb", "MIDI note/CC mapping example"]
        ],
        notes: [
          "Run `vizcore devices midi` before starting the MIDI scene."
        ]
      },
      "live-set" => {
        label: "live-set",
        start_scene: "scenes/live_set.rb",
        files: [
          ["intro_drop_scene.rb", "scenes/live_set.rb", "Two-scene transition flow with beat trigger"]
        ],
        notes: [
          "Use file audio or a microphone input with clear beats for transition triggers."
        ]
      },
      "rubykaigi" => {
        label: "rubykaigi",
        start_scene: "scenes/rubykaigi.rb",
        files: [
          ["rubykaigi_scene.rb", "scenes/rubykaigi.rb", "Ruby conference visual starter"]
        ],
        notes: [
          "This scene uses Ruby-red text and audio-reactive geometry for talk or event visuals."
        ]
      }
    }.freeze

    PLUGIN_SCAFFOLD_FILES = [
      ["plugin_readme.md", "README.md"],
      ["plugin_layer.rb", "lib/{{plugin_name}}.rb"],
      ["plugin_renderer.js", "frontend/{{plugin_name}}-renderer.js"],
      ["plugin_scene.rb", "examples/{{plugin_name}}_scene.rb"]
    ].freeze
    DEFAULT_CAPTURE_PORT = 4579

    desc "start [SCENE_FILE]", "Start vizcore HTTP/WebSocket server"
    option :manifest, type: :string, desc: "Project manifest YAML path"
    option :profile, type: :string, desc: "Project manifest profile name"
    option :host, type: :string, default: Config::DEFAULT_HOST, desc: "Bind host"
    option :port, type: :numeric, default: Config::DEFAULT_PORT, desc: "Bind port"
    option :audio_source, type: :string, desc: "Audio source: mic, file, dummy"
    option :audio_file, type: :string, desc: "Path to audio file used when --audio-source file (wav/mp3/flac)"
    option :audio_device, type: :string, desc: "Audio input device index or name used when --audio-source mic"
    option :feature_file, type: :string, desc: "Replay recorded feature JSON instead of live audio analysis"
    option :control_preset, type: :string, desc: "Control preset JSON for browser HUD and MIDI learn"
    option :noise_gate, type: :numeric, default: Config::DEFAULT_NOISE_GATE, desc: "RMS level below which audio is treated as silence"
    option :bpm, type: :numeric, desc: "Fixed BPM value used with --bpm-lock"
    option :bpm_lock, type: :boolean, default: false, desc: "Lock analysis BPM output to --bpm"
    option :osc_port, type: :numeric, desc: "UDP port for OSC sync (/vizcore/scene, /vizcore/tap)"
    option :reload, type: :boolean, default: Config::DEFAULT_RELOAD, desc: "Reload the scene file when it changes"
    option :projector, type: :boolean, default: false, desc: "Hide browser operator UI for projection output"
    option :allow_public_control, type: :boolean, default: false, desc: "Allow control panel/WebSocket when binding to a public host"
    # Start the Vizcore server with the given scene file.
    #
    # @param scene_file [String] path to a Ruby scene DSL file
    # @raise [Thor::Error] when CLI arguments are invalid
    # @return [void]
    def start(scene_file = nil)
      manifest = load_project_manifest(options[:manifest])
      profile = options[:profile]
      load_manifest_plugins(manifest, profile: profile)
      defaults = manifest&.config_defaults(profile: profile) || {}
      config = Config.new(
        scene_file: scene_file || defaults[:scene_file],
        host: options.fetch(:host),
        port: options.fetch(:port),
        audio_source: options[:audio_source] || defaults[:audio_source] || Config::DEFAULT_AUDIO_SOURCE,
        audio_file: options[:audio_file] || defaults[:audio_file],
        audio_device: options[:audio_device] || defaults[:audio_device],
        feature_file: options[:feature_file] || defaults[:feature_file],
        control_preset: options[:control_preset] || defaults[:control_preset],
        plugin_assets: defaults[:plugin_assets],
        noise_gate: options.fetch(:noise_gate),
        bpm: options[:bpm],
        bpm_lock: options.fetch(:bpm_lock),
        osc_port: options[:osc_port] || defaults[:osc_port],
        reload: options.fetch(:reload),
        projector_mode: options.fetch(:projector),
        allow_public_control: options.fetch(:allow_public_control)
      )
      Server::Runner.new(config).run
    rescue ArgumentError => e
      raise Thor::Error, e.message
    end

    desc "demo", "Start the bundled audio-reactive demo"
    option :host, type: :string, default: Config::DEFAULT_HOST, desc: "Bind host"
    option :port, type: :numeric, default: Config::DEFAULT_PORT, desc: "Bind port"
    option :noise_gate, type: :numeric, default: Config::DEFAULT_NOISE_GATE, desc: "RMS level below which audio is treated as silence"
    option :bpm, type: :numeric, desc: "Fixed BPM value used with --bpm-lock"
    option :bpm_lock, type: :boolean, default: false, desc: "Lock analysis BPM output to --bpm"
    option :control_preset, type: :string, desc: "Control preset JSON for browser HUD and MIDI learn"
    option :osc_port, type: :numeric, desc: "UDP port for OSC sync (/vizcore/scene, /vizcore/tap)"
    option :projector, type: :boolean, default: false, desc: "Hide browser operator UI for projection output"
    option :allow_public_control, type: :boolean, default: false, desc: "Allow control panel/WebSocket when binding to a public host"
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
        noise_gate: options.fetch(:noise_gate),
        bpm: options[:bpm],
        bpm_lock: options.fetch(:bpm_lock),
        control_preset: options[:control_preset],
        osc_port: options[:osc_port],
        projector_mode: options.fetch(:projector),
        allow_public_control: options.fetch(:allow_public_control)
      )
      Server::Runner.new(config).run
    rescue ArgumentError => e
      raise Thor::Error, e.message
    end

    desc "gallery", "Start the bundled example gallery"
    option :host, type: :string, default: Config::DEFAULT_HOST, desc: "Bind host"
    option :port, type: :numeric, default: Vizcore::Server::GalleryRunner::DEFAULT_PORT, desc: "Bind port"
    # Start a browser gallery for bundled example scenes.
    #
    # @return [void]
    def gallery
      Vizcore::Server::GalleryRunner.new(
        host: options.fetch(:host),
        port: options.fetch(:port)
      ).run
    end

    desc "new NAME", "Create a starter project scaffold"
    option :template,
           type: :string,
           default: "standard",
           desc: "Scaffold template: standard, minimal, shader, midi, live-set, rubykaigi"
    # Generate a new Vizcore project scaffold.
    #
    # @param name [String] directory name for the new project
    # @return [void]
    def new(name)
      scaffold = scaffold_template(options.fetch(:template))
      root = Pathname.new(name).expand_path
      FileUtils.mkdir_p(root)

      write_project_readme(root.join("README.md"), project_name: name, scaffold: scaffold)
      scaffold.fetch(:files).each do |template_name, destination, _description|
        write_template(template_name, root.join(destination), project_name: name)
      end

      say("Created project scaffold (#{scaffold.fetch(:label)}): #{root}")
      say("Next: cd #{name} && vizcore start #{scaffold.fetch(:start_scene)}")
    rescue ArgumentError => e
      raise Thor::Error, e.message
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
    option :format, type: :string, default: "text", desc: "Output format: text or json"
    # Load a scene DSL file and print its runtime structure.
    #
    # @param scene_file [String] path to a Ruby scene DSL file
    # @raise [Thor::Error] when scene loading fails
    # @return [void]
    def inspect_scene(scene_file)
      format = options.fetch(:format).to_s
      diagnostics = Vizcore::CLISupport::SceneDiagnostics.new(scene_file: scene_file)
      result = diagnostics.validate
      if format == "json"
        payload = {
          issues: result.issues.map(&:to_h),
          definition: result.definition ? Vizcore::CLISupport::SceneInspector.new(definition: result.definition).to_h : nil
        }
        say(JSON.pretty_generate(payload))
        raise Thor::Error, "scene inspection failed" unless result.definition
        return
      end
      raise Thor::Error, "unsupported inspect format: #{format}" unless format == "text"

      print_issues(result.issues)
      raise Thor::Error, "scene inspection failed" unless result.definition

      diagnostics.inspect_lines(result.definition).each { |line| say(line) }
    end

    desc "validate SCENE_FILE", "Validate a scene DSL file"
    option :strict, type: :boolean, default: false, desc: "Error on unknown layer params and stricter duplicate mappings"
    # Load and validate a scene DSL file without starting the server.
    #
    # @param scene_file [String] path to a Ruby scene DSL file
    # @raise [Thor::Error] when validation fails
    # @return [void]
    def validate(scene_file)
      result = Vizcore::CLISupport::SceneDiagnostics.new(scene_file: scene_file, strict: options.fetch(:strict)).validate
      print_issues(result.issues)
      raise Thor::Error, "scene validation failed" unless result.valid?

      say("Scene valid: #{scene_file}")
    end

    desc "layers", "Print built-in layer capability metadata"
    # Print supported layer types, params, and browser-side capabilities.
    #
    # @return [void]
    def layers
      Vizcore::CLISupport::LayerDocs.new.lines.each { |line| say(line) }
    end

    map "dsl-docs" => :dsl_docs
    desc "dsl-docs", "Print generated Ruby DSL reference"
    # Print generated documentation for the Ruby scene DSL.
    #
    # @return [void]
    def dsl_docs
      Vizcore::CLISupport::DslReference.new.lines.each { |line| say(line) }
    end

    map "shader-docs" => :shader_docs
    desc "shader-docs", "Print custom GLSL shader uniform reference"
    # Print generated documentation for custom GLSL uniforms.
    #
    # @return [void]
    def shader_docs
      Vizcore::CLISupport::ShaderUniformDocs.new.lines.each { |line| say(line) }
    end

    desc "shader COMMAND [NAME]", "Manage custom GLSL shader helpers"
    option :out, type: :string, desc: "Output path for `shader new`"
    # Run custom shader helper commands.
    #
    # @param command [String]
    # @param name [String, nil]
    # @raise [Thor::Error] when the subcommand or arguments are invalid
    # @return [void]
    def shader(command = nil, name = nil)
      case command.to_s
      when "new"
        create_shader_template(name)
      else
        raise Thor::Error, "Unknown shader command: #{command || '(nil)'}. Use `vizcore shader new NAME`."
      end
    rescue ArgumentError => e
      raise Thor::Error, e.message
    end

    desc "plugin COMMAND [NAME]", "Manage Vizcore plugin helpers"
    option :out, type: :string, desc: "Output directory for `plugin new`"
    # Run plugin helper commands.
    #
    # @param command [String, nil]
    # @param name [String, nil]
    # @raise [Thor::Error] when the subcommand or arguments are invalid
    # @return [void]
    def plugin(command = nil, name = nil)
      case command.to_s
      when "new"
        create_plugin_scaffold(name)
      else
        raise Thor::Error, "Unknown plugin command: #{command || '(nil)'}. Use `vizcore plugin new NAME`."
      end
    rescue ArgumentError => e
      raise Thor::Error, e.message
    end

    map "browser-capture" => :browser_capture
    desc "browser-capture URL", "Capture a browser-rendered Vizcore canvas to PNG"
    option :out, type: :string, default: "browser-capture.png", desc: "Output PNG path"
    option :selector, type: :string, default: "#vizcore-canvas", desc: "Element selector to capture"
    option :wait, type: :numeric, default: 1000, desc: "Milliseconds to wait after page load"
    option :width, type: :numeric, default: 1280, desc: "Browser viewport width"
    option :height, type: :numeric, default: 720, desc: "Browser viewport height"
    # Capture browser-rendered output from a running Vizcore server.
    #
    # @param url [String]
    # @raise [Thor::Error] when Playwright capture fails
    # @return [void]
    def browser_capture(url)
      run_browser_capture(
        url,
        out: options.fetch(:out),
        selector: options.fetch(:selector),
        wait: options.fetch(:wait),
        width: options.fetch(:width),
        height: options.fetch(:height)
      )
    end

    desc "capture SCENE_FILE", "Start a temporary server and capture the browser-rendered canvas"
    option :host, type: :string, default: Config::DEFAULT_HOST, desc: "Temporary server host"
    option :port, type: :numeric, default: DEFAULT_CAPTURE_PORT, desc: "Temporary server port"
    option :audio_source, type: :string, default: "dummy", desc: "Audio source: dummy, file, mic"
    option :audio_file, type: :string, desc: "Path to audio file used when --audio-source file"
    option :feature_file, type: :string, desc: "Replay recorded feature JSON instead of live audio analysis"
    option :control_preset, type: :string, desc: "Control preset JSON for browser HUD and MIDI learn"
    option :out, type: :string, default: "browser-capture.png", desc: "Output PNG path"
    option :selector, type: :string, default: "#vizcore-canvas", desc: "Element selector to capture"
    option :wait, type: :numeric, default: 1000, desc: "Milliseconds to wait after page load"
    option :timeout, type: :numeric, default: 10, desc: "Seconds to wait for the temporary server"
    option :width, type: :numeric, default: 1280, desc: "Browser viewport width"
    option :height, type: :numeric, default: 720, desc: "Browser viewport height"
    option :allow_public_control, type: :boolean, default: false, desc: "Allow control panel/WebSocket when binding to a public host"
    # Start Vizcore and capture a browser-rendered canvas from the projector route.
    #
    # @param scene_file [String]
    # @raise [Thor::Error] when server startup or capture fails
    # @return [void]
    def capture(scene_file)
      config = Config.new(
        scene_file: scene_file,
        host: options.fetch(:host),
        port: options.fetch(:port),
        audio_source: options.fetch(:audio_source),
        audio_file: options[:audio_file],
        feature_file: options[:feature_file],
        control_preset: options[:control_preset],
        reload: false,
        projector_mode: true,
        allow_public_control: options.fetch(:allow_public_control)
      )
      validate_snapshot_config!(config)

      pid = Kernel.spawn(*temporary_server_command(config), out: File::NULL, err: File::NULL)
      begin
        wait_for_http("http://#{config.host}:#{config.port}/health", timeout: options.fetch(:timeout))
        run_browser_capture(
          "http://#{config.host}:#{config.port}/projector",
          out: options.fetch(:out),
          selector: options.fetch(:selector),
          wait: options.fetch(:wait),
          width: options.fetch(:width),
          height: options.fetch(:height)
        )
      ensure
        stop_temporary_server(pid)
      end
    rescue StandardError => e
      raise Thor::Error, e.message
    end

    desc "snapshot SCENE_FILE", "Render one scene frame to a PNG snapshot"
    option :audio_source, type: :string, default: "dummy", desc: "Audio source: dummy, file, mic"
    option :audio_file, type: :string, desc: "Path to audio file used when --audio-source file"
    option :audio_device, type: :string, desc: "Audio input device index or name used when --audio-source mic"
    option :noise_gate, type: :numeric, default: Config::DEFAULT_NOISE_GATE, desc: "RMS level below which audio is treated as silence"
    option :bpm, type: :numeric, desc: "Fixed BPM value used with --bpm-lock"
    option :bpm_lock, type: :boolean, default: false, desc: "Lock analysis BPM output to --bpm"
    option :out, type: :string, default: "snapshot.png", desc: "Output PNG path"
    option :width, type: :numeric, default: Vizcore::Renderer::SnapshotRenderer::DEFAULT_WIDTH, desc: "Snapshot width"
    option :height, type: :numeric, default: Vizcore::Renderer::SnapshotRenderer::DEFAULT_HEIGHT, desc: "Snapshot height"
    # Load a scene DSL file and write a software-rendered PNG preview.
    #
    # @param scene_file [String] path to a Ruby scene DSL file
    # @raise [Thor::Error] when scene loading or snapshot writing fails
    # @return [void]
    def snapshot(scene_file)
      config = Config.new(
        scene_file: scene_file,
        audio_source: options.fetch(:audio_source),
        audio_file: options[:audio_file],
        audio_device: options[:audio_device],
        noise_gate: options.fetch(:noise_gate),
        bpm: options[:bpm],
        bpm_lock: options.fetch(:bpm_lock)
      )
      validate_snapshot_config!(config)

      result = Vizcore::Renderer::Snapshot.new(
        config: config,
        width: options.fetch(:width),
        height: options.fetch(:height)
      ).write(out: options.fetch(:out))
      say("Snapshot written: #{result[:path]} (scene=#{result[:scene]}, #{result[:width]}x#{result[:height]})")
    rescue StandardError => e
      raise Thor::Error, e.message
    end

    desc "render SCENE_FILE", "Render a PNG image sequence or MP4 video for a scene"
    option :audio_source, type: :string, default: "dummy", desc: "Audio source: dummy, file, mic"
    option :audio_file, type: :string, desc: "Path to audio file used when --audio-source file"
    option :audio_device, type: :string, desc: "Audio input device index or name used when --audio-source mic"
    option :noise_gate, type: :numeric, default: Config::DEFAULT_NOISE_GATE, desc: "RMS level below which audio is treated as silence"
    option :bpm, type: :numeric, desc: "Fixed BPM value used with --bpm-lock"
    option :bpm_lock, type: :boolean, default: false, desc: "Lock analysis BPM output to --bpm"
    option :out, type: :string, default: "frames", desc: "Output directory for PNG frames, or .mp4 video path"
    option :frames, type: :numeric, default: Vizcore::Renderer::RenderSequence::DEFAULT_FRAME_COUNT, desc: "Number of frames to write"
    option :fps, type: :numeric, default: Vizcore::Renderer::RenderSequence::DEFAULT_FRAME_RATE, desc: "Render frame rate"
    option :width, type: :numeric, default: Vizcore::Renderer::SnapshotRenderer::DEFAULT_WIDTH, desc: "Frame width"
    option :height, type: :numeric, default: Vizcore::Renderer::SnapshotRenderer::DEFAULT_HEIGHT, desc: "Frame height"
    # Load a scene DSL file and write a software-rendered PNG image sequence or MP4.
    #
    # @param scene_file [String] path to a Ruby scene DSL file
    # @raise [Thor::Error] when scene loading or frame writing fails
    # @return [void]
    def render(scene_file)
      config = Config.new(
        scene_file: scene_file,
        audio_source: options.fetch(:audio_source),
        audio_file: options[:audio_file],
        audio_device: options[:audio_device],
        noise_gate: options.fetch(:noise_gate),
        bpm: options[:bpm],
        bpm_lock: options.fetch(:bpm_lock)
      )
      validate_snapshot_config!(config)

      result = Vizcore::Renderer::RenderSequence.new(
        config: config,
        frames: options.fetch(:frames),
        fps: options.fetch(:fps),
        width: options.fetch(:width),
        height: options.fetch(:height)
      ).write(out: options.fetch(:out))
      return say(render_video_message(result)) if result[:format] == :mp4

      say(
        "Frames written: #{result[:path]} " \
        "(scene=#{result[:scene]}, frames=#{result[:frames]}, fps=#{result[:fps]}, #{result[:width]}x#{result[:height]})"
      )
    rescue StandardError => e
      raise Thor::Error, e.message
    end

    map "record-features" => :record_features
    desc "record-features AUDIO_FILE", "Record audio analysis features to JSON"
    option :out, type: :string, default: "features.json", desc: "Output JSON path"
    option :frames, type: :numeric, default: Vizcore::Analysis::FeatureRecorder::DEFAULT_FRAME_COUNT, desc: "Number of analysis frames to record"
    option :fps, type: :numeric, default: Vizcore::Analysis::FeatureRecorder::DEFAULT_FRAME_RATE, desc: "Analysis frame rate"
    option :noise_gate, type: :numeric, default: Config::DEFAULT_NOISE_GATE, desc: "RMS level below which audio is treated as silence"
    option :audio_normalize, type: :boolean, default: false, desc: "Apply adaptive feature normalization"
    option :bpm, type: :numeric, desc: "Fixed BPM value used with --bpm-lock"
    option :bpm_lock, type: :boolean, default: false, desc: "Lock analysis BPM output to --bpm"
    # Analyze an audio file and persist feature frames as JSON.
    #
    # @param audio_file [String] path to WAV/MP3/FLAC audio file
    # @raise [Thor::Error] when audio loading or JSON writing fails
    # @return [void]
    def record_features(audio_file)
      result = Vizcore::Analysis::FeatureRecorder.new(
        audio_file: audio_file,
        frames: options.fetch(:frames),
        fps: options.fetch(:fps),
        noise_gate: options.fetch(:noise_gate),
        audio_normalize: feature_audio_normalize_setting,
        bpm: options[:bpm],
        bpm_lock: options.fetch(:bpm_lock)
      ).write(out: options.fetch(:out))
      say(
        "Features written: #{result[:path]} " \
        "(frames=#{result[:frames]}, fps=#{result[:fps]}, sample_rate=#{result[:sample_rate]})"
      )
    rescue StandardError => e
      raise Thor::Error, e.message
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
        code = issue.respond_to?(:code) && issue.code ? " #{issue.code}" : ""
        say("#{label}#{code} #{issue.message}")
      end
    end

    def validate_snapshot_config!(config)
      raise ArgumentError, "Scene file not found: #{config.scene_file || '(nil)'}" unless config.scene_exists?
      return unless config.audio_source == :file
      return if config.audio_file&.file?

      raise ArgumentError, "Audio file not found: #{config.audio_file || '(nil)'}"
    end

    def create_shader_template(name)
      raise ArgumentError, "shader name is required" if name.to_s.strip.empty?

      destination = options[:out] || Vizcore::CLISupport::ShaderTemplate.default_path(name)
      path = Vizcore::CLISupport::ShaderTemplate.new.write(destination)
      say("Shader template written: #{path}")
    end

    def write_template(template_name, destination, project_name: nil, replacements: {})
      template_path = Vizcore.templates_root.join(template_name)
      values = replacements.transform_keys(&:to_s)
      values["{{project_name}}"] = project_name if project_name
      body = template_path.read
      values.each do |placeholder, value|
        body = body.gsub(placeholder, value.to_s)
      end
      FileUtils.mkdir_p(destination.dirname)
      destination.write(body)
    end

    def write_project_readme(destination, project_name:, scaffold:)
      template_path = Vizcore.templates_root.join("project_readme.md")
      body = template_path.read
                          .gsub("{{project_name}}", project_name)
                          .gsub("{{template_name}}", scaffold.fetch(:label))
                          .gsub("{{start_scene}}", scaffold.fetch(:start_scene))
                          .gsub("{{included_files}}", scaffold_files(scaffold))
                          .gsub("{{template_notes}}", scaffold_notes(scaffold))
      FileUtils.mkdir_p(destination.dirname)
      destination.write(body)
    end

    def scaffold_template(name)
      key = name.to_s.strip.downcase
      key = "standard" if key.empty? || key == "default"
      scaffold = SCAFFOLD_TEMPLATES[key]
      return scaffold if scaffold

      raise ArgumentError, "Unknown template: #{name}. Use one of: #{SCAFFOLD_TEMPLATES.keys.join(', ')}"
    end

    def scaffold_files(scaffold)
      scaffold.fetch(:files).map do |_template_name, destination, description|
        "- `#{destination}`: #{description}"
      end.join("\n")
    end

    def scaffold_notes(scaffold)
      notes = Array(scaffold[:notes])
      return "No extra setup is required." if notes.empty?

      notes.map { |note| "- #{note}" }.join("\n")
    end

    def render_video_message(result)
      "Video written: #{result[:path]} " \
        "(scene=#{result[:scene]}, frames=#{result[:frames]}, fps=#{result[:fps]}, #{result[:width]}x#{result[:height]})"
    end

    def run_browser_capture(url, out:, selector:, wait:, width:, height:)
      script = Vizcore.root.join("scripts", "browser_capture.mjs")
      command = [
        "node",
        script.to_s,
        url.to_s,
        "--out",
        out.to_s,
        "--selector",
        selector.to_s,
        "--wait",
        wait.to_s,
        "--width",
        width.to_s,
        "--height",
        height.to_s
      ]
      success = Kernel.system(*command)
      raise Thor::Error, "browser capture failed" unless success
    end

    def temporary_server_command(config)
      command = [
        Gem.ruby,
        "-I#{Vizcore.root.join('lib')}",
        Vizcore.root.join("exe", "vizcore").to_s,
        "start",
        config.scene_file.to_s,
        "--host",
        config.host,
        "--port",
        config.port.to_s,
        "--audio-source",
        config.audio_source.to_s,
        "--no-reload",
        "--projector"
      ]
      command.concat(["--audio-file", config.audio_file.to_s]) if config.audio_file
      command.concat(["--feature-file", config.feature_file.to_s]) if config.feature_file
      command.concat(["--control-preset", config.control_preset.to_s]) if config.control_preset
      command << "--allow-public-control" if config.allow_public_control?
      command
    end

    def wait_for_http(url, timeout:)
      return true if Float(timeout) <= 0

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Float(timeout)
      uri = URI(url)
      loop do
        response = Net::HTTP.get_response(uri)
        return true if response.is_a?(Net::HTTPSuccess)
        raise "Timed out waiting for #{url}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep(0.1)
      rescue StandardError
        raise "Timed out waiting for #{url}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep(0.1)
      end
    end

    def stop_temporary_server(pid)
      Process.kill("TERM", pid)
      Process.wait(pid)
    rescue Errno::ECHILD, Errno::ESRCH
      nil
    end

    def create_plugin_scaffold(name)
      metadata = plugin_scaffold_metadata(name)
      root = Pathname.new(options[:out] || metadata.fetch(:plugin_name)).expand_path
      replacements = metadata.transform_keys { |key| "{{#{key}}}" }

      FileUtils.mkdir_p(root)
      PLUGIN_SCAFFOLD_FILES.each do |template_name, destination|
        rendered_destination = destination.dup
        replacements.each do |placeholder, value|
          rendered_destination = rendered_destination.gsub(placeholder, value.to_s)
        end
        write_template(template_name, root.join(rendered_destination), replacements: replacements)
      end

      say("Created plugin scaffold: #{root}")
      say("Next: require_relative \"#{root.basename}/lib/#{metadata.fetch(:plugin_name)}\" in your scene")
    end

    def plugin_scaffold_metadata(name)
      raw_name = name.to_s.strip
      raise ArgumentError, "plugin name is required" if raw_name.empty?

      plugin_name = normalize_plugin_name(raw_name)
      raise ArgumentError, "plugin name must contain letters or numbers" if plugin_name.empty?

      module_name = plugin_module_name(plugin_name)
      {
        plugin_name: plugin_name,
        plugin_module: module_name,
        plugin_renderer: "render#{module_name}",
        plugin_type: "#{plugin_name}_layer",
        plugin_title: plugin_name.split("_").map(&:capitalize).join(" ")
      }
    end

    def normalize_plugin_name(name)
      name.gsub(/([a-z\d])([A-Z])/, "\\1_\\2")
          .tr("- ", "__")
          .gsub(/[^a-zA-Z0-9_]/, "_")
          .gsub(/_+/, "_")
          .downcase
          .sub(/\A_+/, "")
          .sub(/_+\z/, "")
    end

    def plugin_module_name(plugin_name)
      module_name = plugin_name.split("_").map(&:capitalize).join
      module_name.match?(/\A[A-Z]/) ? module_name : "Plugin#{module_name}"
    end

    def load_project_manifest(path)
      return nil if path.to_s.strip.empty?

      Vizcore::ProjectManifest.load(path)
    end

    def load_manifest_plugins(manifest, profile: nil)
      return unless manifest

      manifest.plugins(profile: profile).each do |plugin|
        Vizcore.plugin(plugin)
      rescue LoadError => e
        raise Thor::Error, "Failed to load manifest plugin #{plugin}: #{e.message}"
      end
    end

    def feature_audio_normalize_setting
      return nil unless options.fetch(:audio_normalize)

      { mode: :adaptive }
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
