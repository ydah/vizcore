# frozen_string_literal: true

require "tmpdir"
require "vizcore/config"
require "vizcore/renderer/snapshot"

RSpec.describe Vizcore::Renderer::Snapshot do
  it "writes a PNG snapshot for a scene" do
    Dir.mktmpdir("vizcore-snapshot") do |dir|
      out = File.join(dir, "snapshot.png")
      config = Vizcore::Config.new(
        scene_file: Vizcore.root.join("examples", "basic.rb").to_s,
        audio_source: :dummy
      )

      result = described_class.new(config: config, width: 320, height: 180).write(out: out)

      expect(result).to include(path: Pathname.new(out).expand_path, scene: "basic", width: 320, height: 180)
      expect(File.binread(out, 8)).to eq(Vizcore::Renderer::PngWriter::SIGNATURE)
      expect(File.size(out)).to be > 128
    end
  end
end
