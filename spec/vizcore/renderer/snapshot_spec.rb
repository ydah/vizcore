# frozen_string_literal: true

require "digest"
require "tmpdir"
require "zlib"
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

  it "matches the golden scanline digest for the basic dummy frame" do
    config = Vizcore::Config.new(
      scene_file: Vizcore.root.join("examples", "basic.rb").to_s,
      audio_source: :dummy
    )
    frame_source = Vizcore::Renderer::SceneFrameSource.new(config: config)
    frame_source.start
    frame = frame_source.capture
    png = Vizcore::Renderer::SnapshotRenderer.new(width: 160, height: 90).render(
      scene: frame.fetch(:scene),
      audio: frame.fetch(:audio)
    )

    expect(Digest::SHA256.hexdigest(png_scanlines(png))).to eq(
      "9a90aa759e28ff2f22e05c0bc78e16a9d233adbb6d61cc2f22f670bbc29f7728"
    )
  ensure
    frame_source&.stop
  end

  def png_scanlines(png)
    offset = Vizcore::Renderer::PngWriter::SIGNATURE.bytesize
    idat = +"".b

    while offset < png.bytesize
      length = png.byteslice(offset, 4).unpack1("N")
      type = png.byteslice(offset + 4, 4)
      data = png.byteslice(offset + 8, length)
      idat << data if type == "IDAT"
      offset += 12 + length
    end

    Zlib::Inflate.inflate(idat)
  end
end
