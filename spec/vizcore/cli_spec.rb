# frozen_string_literal: true

require "pathname"
require "tmpdir"
require "vizcore/cli"

RSpec.describe Vizcore::CLI do
  describe ".start" do
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
  end
end
