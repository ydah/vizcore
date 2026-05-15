# frozen_string_literal: true

require "tmpdir"
require "vizcore/config"
require "vizcore/renderer/render_sequence"

RSpec.describe Vizcore::Renderer::RenderSequence do
  it "writes a PNG image sequence for a scene" do
    Dir.mktmpdir("vizcore-render-sequence") do |dir|
      config = Vizcore::Config.new(
        scene_file: Vizcore.root.join("examples", "basic.rb").to_s,
        audio_source: :dummy
      )

      result = described_class.new(config: config, frames: 3, fps: 15, width: 160, height: 90).write(out: dir)
      frames = Dir[File.join(dir, "frame_*.png")].sort

      expect(result).to include(path: Pathname.new(dir).expand_path, frames: 3, fps: 15.0, width: 160, height: 90, scene: "basic")
      expect(frames.map { |path| File.basename(path) }).to eq(%w[frame_00001.png frame_00002.png frame_00003.png])
      expect(File.binread(frames.first, 8)).to eq(Vizcore::Renderer::PngWriter::SIGNATURE)
    end
  end

  it "rejects direct video output paths until mp4 encoding is supported" do
    config = Vizcore::Config.new(
      scene_file: Vizcore.root.join("examples", "basic.rb").to_s,
      audio_source: :dummy
    )

    expect do
      described_class.new(config: config, frames: 1).write(out: "movie.mp4")
    end.to raise_error(ArgumentError, /Video output is not supported yet/)
  end
end
