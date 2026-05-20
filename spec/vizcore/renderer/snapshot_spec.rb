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

  it "renders extended shape primitives in software snapshots" do
    scene = {
      layers: [
        {
          name: :shapes,
          type: :shape,
          params: {
            shape_schema_version: 2,
            shapes: [
              { kind: :rect, width: 160, height: 80, transform: { rotate: 8 } },
              { kind: :polygon, points: [[0, 80], [-70, -40], [70, -40]] },
              { kind: :path, detail: 8, commands: [["M", -90, 0], ["C", -30, 80, 30, -80, 90, 0]] },
              { kind: :path, detail: 12, commands: [["M", -80, -45], ["A", 40, 24, 0, 0, 1, 0, -45]] },
              { kind: :star, points: 5, radius: 60, inner_radius: 24, transform: { translate: { x: 180, y: 0 } } }
            ]
          }
        }
      ]
    }

    png = Vizcore::Renderer::SnapshotRenderer.new(width: 160, height: 90).render(
      scene: scene,
      audio: { amplitude: 0.4, beat_pulse: 0.2, bands: { low: 0.1, high: 0.3 } }
    )

    expect(png.byteslice(0, 8)).to eq(Vizcore::Renderer::PngWriter::SIGNATURE)
    expect(png.bytesize).to be > 128
  end

  it "caps flattened path segments in software snapshots" do
    canvas = Class.new do
      attr_reader :lines

      def initialize
        @lines = []
      end

      def draw_line(*args, **kwargs)
        @lines << [args, kwargs]
      end
    end.new

    renderer = Vizcore::Renderer::SnapshotRenderer.new(width: 160, height: 90)
    renderer.send(
      :render_path_shape,
      canvas,
      {
        kind: :path,
        detail: 16,
        max_segments: 3,
        commands: [["M", 0, 0], ["C", 20, 80, 80, -80, 100, 0], ["L", 120, 0]]
      },
      [255, 255, 255],
      1.0,
      { units: :logical }
    )

    expect(canvas.lines.length).to eq(3)
  end

  it "uses path tolerance for adaptive software snapshot flattening" do
    canvas = Class.new do
      attr_reader :lines

      def initialize
        @lines = []
      end

      def draw_line(*args, **kwargs)
        @lines << [args, kwargs]
      end
    end.new

    renderer = Vizcore::Renderer::SnapshotRenderer.new(width: 160, height: 90)
    renderer.send(
      :render_path_shape,
      canvas,
      { kind: :path, detail: 64, tolerance: 80, commands: [["M", 0, 0], ["Q", 50, 10, 100, 0]] },
      [255, 255, 255],
      1.0,
      { units: :logical }
    )

    expect(canvas.lines.length).to eq(1)
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
