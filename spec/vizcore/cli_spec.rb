# frozen_string_literal: true

require "pathname"
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

    it "validates a scene file" do
      Dir.mktmpdir("vizcore-cli-validate") do |dir|
        scene_path = File.join(dir, "scene.rb")
        File.write(scene_path, "Vizcore.define { scene(:main) { layer(:cube) { type :wireframe_cube } } }")

        expect do
          described_class.start(["validate", scene_path])
        end.to output(/Scene valid: #{Regexp.escape(scene_path)}/).to_stdout
      end
    end

    it "inspects a scene file" do
      Dir.mktmpdir("vizcore-cli-inspect") do |dir|
        scene_path = File.join(dir, "scene.rb")
        File.write(scene_path, "Vizcore.define { scene(:main) { layer(:cube) { type :wireframe_cube } } }")

        expect do
          described_class.start(["inspect", scene_path])
        end.to output(/Scenes:\n  main\n    layer cube \(wireframe_cube\)/).to_stdout
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
          "--no-reload",
          "--projector"
        ]
      )

      expect(Vizcore::Server::Runner).to have_received(:new) do |config|
        expect(config.audio_source).to eq(:file)
        expect(config.audio_file.to_s).to end_with("spec/fixtures/audio/pulse16_mono.wav")
        expect(config.audio_device).to eq("5")
        expect(config.noise_gate).to eq(0.03)
        expect(config.bpm).to eq(128.0)
        expect(config.bpm_lock?).to eq(true)
        expect(config.reload?).to eq(false)
        expect(config.projector_mode).to eq(true)
      end
      expect(runner).to have_received(:run)
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
