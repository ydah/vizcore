# frozen_string_literal: true

require "json"
require "fileutils"
require "pathname"
require "stringio"
require "tmpdir"
require "vizcore/cli"

RSpec.describe Vizcore::CLI do
  describe ".start" do
    let(:runner) { instance_double(Vizcore::Server::Runner, run: nil) }

    before do
      allow(Vizcore::Server::Runner).to receive(:new).and_return(runner)
    end

    it "creates a project scaffold" do
      Dir.mktmpdir("vizcore-cli") do |dir|
        Dir.chdir(dir) do
          expect do
            described_class.start(["new", "my_show"])
          end.to output(/Created project scaffold/).to_stdout

          expect(Pathname("my_show/README.md")).to exist
          expect(Pathname("my_show/scenes/basic.rb")).to exist
          expect(Pathname("my_show/scenes/intro_drop.rb")).to exist
          expect(Pathname("my_show/scenes/midi_control.rb")).to exist
          expect(Pathname("my_show/scenes/custom_shader.rb")).to exist
          expect(Pathname("my_show/shaders/custom_wave.frag")).to exist
          expect(Pathname("my_show/shaders")).to exist
          expect(Pathname("my_show/README.md").read).to include("Template: `standard`")
        end
      end
    end

    it "creates focused project scaffolds from templates" do
      templates = {
        "minimal" => ["scenes/basic.rb"],
        "shader" => ["scenes/custom_shader.rb", "shaders/custom_wave.frag"],
        "midi" => ["scenes/midi_control.rb"],
        "live-set" => ["scenes/live_set.rb"],
        "rubykaigi" => ["scenes/rubykaigi.rb"]
      }

      Dir.mktmpdir("vizcore-cli-templates") do |dir|
        Dir.chdir(dir) do
          templates.each do |template, expected_paths|
            project = "show_#{template.tr('-', '_')}"
            expect do
              described_class.start(["new", project, "--template", template])
            end.to output(/Created project scaffold \(#{Regexp.escape(template)}\)/).to_stdout

            expected_paths.each do |path|
              expect(Pathname(project).join(path)).to exist
            end
            expect(Pathname(project).join("README.md").read).to include("Template: `#{template}`")
          end
        end
      end
    end

    it "rejects unknown project scaffold templates" do
      expect do
        expect do
          described_class.start(["new", "bad_show", "--template", "unknown"])
        end.to raise_error(SystemExit)
      end.to output(/Unknown template: unknown/).to_stderr
    end

    it "prints audio devices" do
      expect do
        described_class.start(["devices", "audio"])
      end.to output(/Audio devices:/).to_stdout
    end

    it "prints midi devices" do
      allow(Vizcore::Audio::InputManager).to receive(:available_midi_devices)
        .and_return([{ id: "2", name: "Launchpad Mini MK3" }])

      expect do
        described_class.start(["devices", "midi"])
      end.to output(/MIDI devices:\n  - 2: Launchpad Mini MK3/).to_stdout
    end

    it "prints doctor checks" do
      check = Vizcore::CLISupport::Doctor::Check.new(
        name: "Ruby",
        status: :ok,
        message: "3.2.0 satisfies >= 3.2.0"
      )
      report = Vizcore::CLISupport::Doctor::Report.new(checks: [check])
      doctor = instance_double(Vizcore::CLISupport::Doctor, call: report)
      allow(Vizcore::CLISupport::Doctor).to receive(:new).and_return(doctor)

      expect do
        described_class.start(["doctor"])
      end.to output(/\[ok\] Ruby: 3\.2\.0 satisfies >= 3\.2\.0/).to_stdout
    end

    it "prints optional feature flags as JSON" do
      allow(Vizcore).to receive(:features).and_return(mic: false, midi: true, ffmpeg: true)

      expect do
        described_class.start(["features", "--format", "json"])
      end.to output(/"mic": false.*"midi": true/m).to_stdout
    end

    it "calibrates dummy audio input" do
      expect do
        described_class.start(
          [
            "calibrate",
            "audio",
            "--audio-source",
            "dummy",
            "--duration",
            "0.05",
            "--fps",
            "2"
          ]
        )
      end.to output(/Audio calibration:.*recommended_noise_gate:/m).to_stdout
    end

    it "validates a scene file" do
      Dir.mktmpdir("vizcore-cli-validate") do |dir|
        scene_path = File.join(dir, "scene.rb")
        File.write(scene_path, "Vizcore.define { scene(:main) { layer(:cube) { type :wireframe_cube } } }")

        expect do
          described_class.start(["validate", scene_path])
        end.to output(/Scene valid: #{Regexp.escape(scene_path)}/).to_stdout
      end
    end

    it "prints issue codes for strict validation" do
      Dir.mktmpdir("vizcore-cli-validate-strict") do |dir|
        scene_path = File.join(dir, "scene.rb")
        File.write(scene_path, "Vizcore.define { scene(:main) { layer(:cube) { type :wireframe_cube; opactiy 0.5 } } }")

        expect do
          expect do
            described_class.start(["validate", scene_path, "--strict"])
          end.to raise_error(SystemExit)
        end.to output(/E_UNKNOWN_LAYER_PARAM .*opactiy/).to_stdout
      end
    end

    it "inspects a scene file" do
      Dir.mktmpdir("vizcore-cli-inspect") do |dir|
        scene_path = File.join(dir, "scene.rb")
        File.write(
          scene_path,
          <<~RUBY
            Vizcore.define do
              scene(:main) { layer(:cube) { type :wireframe_cube } }
              scene(:drop) { layer(:blob) { type :radial_blob } }
              timeline do
                at beats(0), scene: :main
                at beats(8), scene: :drop
              end
            end
          RUBY
        )

        expect do
          described_class.start(["inspect", scene_path])
        end.to output(
          /Scenes:\n  main\n    layer cube \(wireframe_cube\).*Timeline 1:\n  0\.0 beats -> main\n  8\.0 beats -> drop/m
        ).to_stdout
      end
    end

    it "inspects a scene file as json" do
      Dir.mktmpdir("vizcore-cli-inspect-json") do |dir|
        scene_path = File.join(dir, "scene.rb")
        File.write(scene_path, "Vizcore.define { scene(:main) { layer(:cube) { type :wireframe_cube } } }")

        original_stdout = $stdout
        stdout = StringIO.new
        $stdout = stdout
        described_class.start(["inspect", scene_path, "--format", "json"])
        output = stdout.string
        $stdout = original_stdout
        payload = JSON.parse(output)

        expect(payload.fetch("issues")).to eq([])
        expect(payload.dig("definition", "scenes", 0, "name")).to eq("main")
        expect(payload.dig("definition", "scenes", 0, "layers", 0, "name")).to eq("cube")
      ensure
        $stdout = original_stdout if original_stdout
      end
    end

    it "runs validate and inspect against a bundled example" do
      expect do
        described_class.start(["validate", "examples/basic.rb"])
      end.to output(/Scene valid: examples\/basic\.rb/).to_stdout

      expect do
        described_class.start(["inspect", "examples/basic.rb"])
      end.to output(/Scenes:\n  basic\n    layer wireframe_cube \(wireframe_cube\)/).to_stdout
    end

    it "prints generated shader uniform docs" do
      expect do
        described_class.start(["shader-docs"])
      end.to output(/# Vizcore Shader Uniforms.*`u_amplitude`.*`u_onset`.*`u_param_<name>`/m).to_stdout
    end

    it "prints layer capability metadata" do
      expect do
        described_class.start(["layers"])
      end.to output(/# Vizcore Layer Capabilities.*## particle_field.*Params:.*count: Integer.*Built-in shaders:/m).to_stdout
    end

    it "prints generated Ruby DSL reference" do
      expect do
        described_class.start(["dsl-docs"])
      end.to output(/# Vizcore Ruby DSL Reference.*`scene :name, extends: :base.*`key "d" \{ switch_scene :drop \}`.*Mapping sources:.*beat_confidence.*`particle_field`/m).to_stdout
    end

    it "creates a custom shader template" do
      Dir.mktmpdir("vizcore-cli-shader") do |dir|
        Dir.chdir(dir) do
          expect do
            described_class.start(["shader", "new", "liquid-wave"])
          end.to output(%r{Shader template written: shaders/liquid-wave\.frag}).to_stdout

          shader = Pathname("shaders/liquid-wave.frag")
          expect(shader).to exist
          expect(shader.read).to include("#version 300 es", "uniform float u_amplitude;", "uniform float u_onset;", "out vec4 outColor;")
        end
      end
    end

    it "creates a plugin scaffold" do
      Dir.mktmpdir("vizcore-cli-plugin") do |dir|
        Dir.chdir(dir) do
          expect do
            described_class.start(["plugin", "new", "laser-grid"])
          end.to output(%r{Created plugin scaffold: .*/laser_grid}).to_stdout

          expect(Pathname("laser_grid/README.md")).to exist
          expect(Pathname("laser_grid/lib/laser_grid.rb")).to exist
          expect(Pathname("laser_grid/frontend/laser_grid-renderer.js")).to exist
          expect(Pathname("laser_grid/examples/laser_grid_scene.rb")).to exist
          expect(Pathname("laser_grid/lib/laser_grid.rb").read).to include("type: LAYER_TYPE", "LAYER_TYPE = :laser_grid_layer")
          expect(Pathname("laser_grid/frontend/laser_grid-renderer.js").read).to include(
            'const layerType = "laser_grid_layer"',
            "globalThis.VizcorePlugins"
          )
        end
      end
    end

    it "checks a plugin scaffold" do
      Dir.mktmpdir("vizcore-cli-plugin-check") do |dir|
        Dir.chdir(dir) do
          described_class.start(["plugin", "new", "laser-grid"])

          expect do
            described_class.start(["plugin", "check", "laser_grid"])
          end.to output(/Ruby layer: .*valid Ruby syntax.*Frontend renderer: .*is loadable.*Example scene: .*valid Ruby syntax/m).to_stdout
        end
      end
    end

    it "runs browser capture helper" do
      expect(Kernel).to receive(:system).with(
        "node",
        Vizcore.root.join("scripts", "browser_capture.mjs").to_s,
        "http://127.0.0.1:4567/projector",
        "--out",
        "browser.png",
        "--selector",
        "#vizcore-canvas",
        "--wait",
        "250",
        "--width",
        "640",
        "--height",
        "360"
      ).and_return(true)

      described_class.start(
        [
          "browser-capture",
          "http://127.0.0.1:4567/projector",
          "--out",
          "browser.png",
          "--wait",
          "250",
          "--width",
          "640",
          "--height",
          "360"
        ]
      )
    end

    it "starts a temporary server for scene browser capture" do
      expect(Kernel).to receive(:spawn).with(
        Gem.ruby,
        "-I#{Vizcore.root.join('lib')}",
        Vizcore.root.join("exe", "vizcore").to_s,
        "start",
        Pathname.new("examples/basic.rb").expand_path.to_s,
        "--host",
        "127.0.0.1",
        "--port",
        "4579",
        "--audio-source",
        "dummy",
        "--no-reload",
        "--projector",
        out: File::NULL,
        err: File::NULL
      ).and_return(12_345)
      expect(Kernel).to receive(:system).with(
        "node",
        Vizcore.root.join("scripts", "browser_capture.mjs").to_s,
        "http://127.0.0.1:4579/projector",
        "--out",
        "scene-browser.png",
        "--selector",
        "#vizcore-canvas",
        "--wait",
        "0",
        "--width",
        "320",
        "--height",
        "180",
        "--wait-for-frame",
        "--frame-timeout",
        "10000"
      ).and_return(true)
      expect(Process).to receive(:kill).with("TERM", 12_345)
      expect(Process).to receive(:wait).with(12_345)

      described_class.start(
        [
          "capture",
          "examples/basic.rb",
          "--out",
          "scene-browser.png",
          "--wait",
          "0",
          "--timeout",
          "0",
          "--width",
          "320",
          "--height",
          "180"
        ]
      )
    end

    it "writes a PNG scene snapshot" do
      Dir.mktmpdir("vizcore-cli-snapshot") do |dir|
        out = File.join(dir, "snapshot.png")

        expect do
          described_class.start(
            [
              "snapshot",
              "examples/basic.rb",
              "--audio-source",
              "dummy",
              "--out",
              out,
              "--width",
              "320",
              "--height",
              "180"
            ]
          )
        end.to output(/Snapshot written: #{Regexp.escape(out)}/).to_stdout

        expect(File.binread(out, 8)).to eq(Vizcore::Renderer::PngWriter::SIGNATURE)
      end
    end

    it "writes a PNG image sequence" do
      Dir.mktmpdir("vizcore-cli-render") do |dir|
        out = File.join(dir, "frames")

        expect do
          described_class.start(
            [
              "render",
              "examples/basic.rb",
              "--audio-source",
              "dummy",
              "--out",
              out,
              "--frames",
              "2",
              "--fps",
              "15",
              "--width",
              "160",
              "--height",
              "90"
            ]
          )
        end.to output(/Frames written: #{Regexp.escape(out)}/).to_stdout

        frames = Dir[File.join(out, "frame_*.png")].sort
        expect(frames.map { |path| File.basename(path) }).to eq(%w[frame_00001.png frame_00002.png])
        expect(File.binread(frames.first, 8)).to eq(Vizcore::Renderer::PngWriter::SIGNATURE)
      end
    end

    it "prints MP4 render output metadata" do
      Dir.mktmpdir("vizcore-cli-render-mp4") do |dir|
        out = File.join(dir, "movie.mp4")
        sequence = instance_double(
          Vizcore::Renderer::RenderSequence,
          write: {
            path: Pathname.new(out).expand_path,
            format: :mp4,
            scene: "basic",
            frames: 2,
            fps: 15.0,
            width: 160,
            height: 90
          }
        )
        allow(Vizcore::Renderer::RenderSequence).to receive(:new).and_return(sequence)

        expect do
          described_class.start(
            [
              "render",
              "examples/basic.rb",
              "--audio-source",
              "dummy",
              "--out",
              out,
              "--frames",
              "2",
              "--fps",
              "15",
              "--width",
              "160",
              "--height",
              "90"
            ]
          )
        end.to output(/Video written: #{Regexp.escape(Pathname.new(out).expand_path.to_s)}/).to_stdout
      end
    end

    it "passes render range and seed options to render sequence" do
      sequence = instance_double(
        Vizcore::Renderer::RenderSequence,
        write: {
          path: Pathname.new("frames").expand_path,
          format: :png_sequence,
          scene: "basic",
          frames: 3,
          fps: 12.0,
          width: 160,
          height: 90
        }
      )
      allow(Vizcore::Renderer::RenderSequence).to receive(:new).and_return(sequence)

      described_class.start(
        [
          "render",
          "examples/basic.rb",
          "--audio-source",
          "dummy",
          "--duration",
          "0.25",
          "--fps",
          "12",
          "--from-frame",
          "2",
          "--to-frame",
          "4",
          "--resume",
          "--seed",
          "42",
          "--transparent",
          "--progress",
          "--codec",
          "libx264",
          "--bitrate",
          "4M",
          "--crf",
          "18",
          "--pix-fmt",
          "yuv444p"
        ]
      )

      expect(Vizcore::Renderer::RenderSequence).to have_received(:new).with(
        hash_including(
          duration: 0.25,
          fps: 12,
          from_frame: 2,
          to_frame: 4,
          resume: true,
          seed: 42,
          transparent: true,
          video_codec: "libx264",
          video_bitrate: "4M",
          video_crf: "18",
          pixel_format: "yuv444p",
          progress_reporter: an_instance_of(Proc)
        )
      )
    end

    it "records audio features to JSON" do
      Dir.mktmpdir("vizcore-cli-features") do |dir|
        audio_file = Vizcore.root.join("spec", "fixtures", "audio", "kick_120bpm.wav")
        out = File.join(dir, "features.json")

        expect do
          described_class.start(
            [
              "record-features",
              audio_file.to_s,
              "--out",
              out,
              "--frames",
              "2",
              "--fps",
              "30",
              "--noise-gate",
              "0"
            ]
          )
        end.to output(/Features written: #{Regexp.escape(out)}/).to_stdout

        payload = JSON.parse(File.read(out))
        expect(payload.fetch("features").length).to eq(2)
        expect(payload.dig("metadata", "fps")).to eq(30.0)
      end
    end

    it "passes audio options to config" do
      described_class.start(
        [
          "start",
          "examples/basic.rb",
          "--audio-source",
          "file",
          "--audio-file",
          "spec/fixtures/audio/pulse16_mono.wav",
          "--audio-device",
          "5",
          "--noise-gate",
          "0.03",
          "--bpm",
          "128",
          "--bpm-lock",
          "--feature-file",
          "features.json",
          "--control-preset",
          "controls.json",
          "--osc-port",
          "9000",
          "--no-reload",
          "--projector",
          "--allow-public-control"
        ]
      )

      expect(Vizcore::Server::Runner).to have_received(:new) do |config|
        expect(config.audio_source).to eq(:file)
        expect(config.audio_file.to_s).to end_with("spec/fixtures/audio/pulse16_mono.wav")
        expect(config.audio_device).to eq("5")
        expect(config.noise_gate).to eq(0.03)
        expect(config.bpm).to eq(128.0)
        expect(config.bpm_lock?).to eq(true)
        expect(config.feature_file.to_s).to end_with("features.json")
        expect(config.control_preset.to_s).to end_with("controls.json")
        expect(config.osc_port).to eq(9000)
        expect(config.reload?).to eq(false)
        expect(config.projector_mode).to eq(true)
        expect(config.allow_public_control?).to eq(true)
      end
      expect(runner).to have_received(:run)
    end

    it "starts from a project manifest" do
      Dir.mktmpdir("vizcore-cli-manifest") do |dir|
        scene_path = File.join(dir, "scenes", "show.rb")
        control_path = File.join(dir, "controls", "live.json")
        FileUtils.mkdir_p(File.dirname(scene_path))
        FileUtils.mkdir_p(File.dirname(control_path))
        File.write(
          File.join(dir, "vizcore.yml"),
          <<~YAML
            scene: scenes/show.rb
            audio:
              source: file
              file: audio/show.wav
            control_preset: controls/live.json
            plugin_assets:
              - frontend/laser.js
            osc_port: 9001
            profiles:
              rehearsal:
                audio:
                  source: dummy
                plugin_assets:
                  - frontend/rehearsal.js
          YAML
        )

        described_class.start(["start", "--manifest", File.join(dir, "vizcore.yml"), "--profile", "rehearsal"])

        expect(Vizcore::Server::Runner).to have_received(:new) do |config|
          expect(config.scene_file.to_s).to eq(Pathname.new(scene_path).expand_path.to_s)
          expect(config.audio_source).to eq(:dummy)
          expect(config.audio_file.to_s).to eq(Pathname.new(dir).join("audio/show.wav").expand_path.to_s)
          expect(config.control_preset.to_s).to eq(Pathname.new(control_path).expand_path.to_s)
          expect(config.plugin_assets.map(&:to_s)).to eq(
            [
              Pathname.new(dir).join("frontend/laser.js").expand_path.to_s,
              Pathname.new(dir).join("frontend/rehearsal.js").expand_path.to_s
            ]
          )
          expect(config.osc_port).to eq(9001)
        end
      end
    end

    it "starts the bundled demo with bundled audio" do
      described_class.start(["demo", "--port", "4568", "--noise-gate", "0.02", "--projector"])

      expect(Vizcore::Server::Runner).to have_received(:new) do |config|
        expect(config.scene_file.to_s).to end_with("examples/rhythm_geometry.rb")
        expect(config.audio_source).to eq(:file)
        expect(config.audio_file.to_s).to end_with("examples/assets/complex_demo_loop.wav")
        expect(config.port).to eq(4568)
        expect(config.noise_gate).to eq(0.02)
        expect(config.projector_mode).to eq(true)
      end
      expect(runner).to have_received(:run)
    end

    it "starts the bundled example gallery" do
      gallery_runner = instance_double(Vizcore::Server::GalleryRunner, run: nil)
      allow(Vizcore::Server::GalleryRunner).to receive(:new).and_return(gallery_runner)

      described_class.start(["gallery", "--port", "4571"])

      expect(Vizcore::Server::GalleryRunner).to have_received(:new).with(
        host: "127.0.0.1",
        port: 4571
      )
      expect(gallery_runner).to have_received(:run)
    end
  end
end
