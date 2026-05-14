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
        end
      end
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
          "0.03"
        ]
      )

      expect(Vizcore::Server::Runner).to have_received(:new) do |config|
        expect(config.audio_source).to eq(:file)
        expect(config.audio_file.to_s).to end_with("spec/fixtures/audio/pulse16_mono.wav")
        expect(config.audio_device).to eq("5")
        expect(config.noise_gate).to eq(0.03)
      end
      expect(runner).to have_received(:run)
    end
  end
end
