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
      expect do
        described_class.start(["devices", "midi"])
      end.to output(/MIDI devices:/).to_stdout
    end

    it "passes --audio-source and --audio-file to config" do
      described_class.start(
        [
          "start",
          "examples/basic.rb",
          "--audio-source",
          "file",
          "--audio-file",
          "spec/fixtures/audio/pulse16_mono.wav"
        ]
      )

      expect(Vizcore::Server::Runner).to have_received(:new) do |config|
        expect(config.audio_source).to eq(:file)
        expect(config.audio_file.to_s).to end_with("spec/fixtures/audio/pulse16_mono.wav")
      end
      expect(runner).to have_received(:run)
    end
  end
end
