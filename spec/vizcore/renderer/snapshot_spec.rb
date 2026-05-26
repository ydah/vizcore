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

  describe "palette_color" do
    it "interpolates between neighboring palette entries" do
      renderer = Vizcore::Renderer::SnapshotRenderer.new(width: 8, height: 8)
      params = { palette: ["#000000", "#ffffff", "#ff0000"] }

      expect(renderer.send(:palette_color, params, 0)).to eq("#000000")
      expect(renderer.send(:palette_color, params, 1)).to eq("#ffffff")
      expect(renderer.send(:palette_color, params, 0.5)).to eq("#808080")
      expect(renderer.send(:palette_color, params, 2.25)).to eq("#bf0000")
    end

    it "resolves explicit gradient colors in layer params" do
      renderer = Vizcore::Renderer::SnapshotRenderer.new(width: 8, height: 8)
      params = {
        color: {
          gradient: {
            colors: ["#000000", "#ffffff"],
            position: 0.5
          }
        }
      }

    expect(renderer.send(:configured_color, params)).to eq("#808080")
  end
end

  it "can render a transparent PNG background" do
    png = Vizcore::Renderer::SnapshotRenderer.new(width: 8, height: 8, transparent: true).render(
      scene: { layers: [{ name: :empty_shape, type: :shape, params: { shapes: [] } }] },
      audio: { amplitude: 0.0, beat_pulse: 0.0, bands: { low: 0.0, high: 0.0 } }
    )
    scanlines = png_scanlines(png)

    expect(scanlines.getbyte(0)).to eq(0)
    expect(scanlines.getbyte(4)).to eq(0)
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

  it "advances offline frame source through transition rules" do
    Dir.mktmpdir("vizcore-frame-source") do |dir|
      scene_path = File.join(dir, "scene.rb")
      File.write(scene_path, <<~RUBY)
        Vizcore.define do
          scene :intro do
            layer(:intro_layer) { type :geometry }
          end

          scene :drop do
            layer(:drop_layer) { type :shader }
          end

          transition from: :intro, to: :drop do
            trigger { frame_count >= 1 }
          end
        end
      RUBY
      config = Vizcore::Config.new(scene_file: scene_path, audio_source: :dummy)
      frame_source = Vizcore::Renderer::SceneFrameSource.new(config: config, frame_rate: 30)
      frame_source.start

      first = frame_source.capture
      second = frame_source.capture

      expect(first[:scene_name]).to eq("intro")
      expect(first.dig(:scene, :schema_version)).to eq("vizcore.scene.v1")
      expect(second[:scene_name]).to eq("drop")
      expect(second.dig(:scene, :layers, 0, :name)).to eq("drop_layer")
    ensure
      frame_source&.stop
    end
  end

  it "starts from the first timeline scene" do
    Dir.mktmpdir("vizcore-frame-source-timeline") do |dir|
      scene_path = File.join(dir, "scene.rb")
      File.write(scene_path, <<~RUBY)
        Vizcore.define do
          scene :intro do
            layer(:intro_layer) { type :geometry }
          end

          scene :drop do
            layer(:drop_layer) { type :geometry }
          end

          timeline do
            at beats(0), scene: :drop
            at beats(4), scene: :intro
          end
        end
      RUBY
      config = Vizcore::Config.new(scene_file: scene_path, audio_source: :dummy)
      frame_source = Vizcore::Renderer::SceneFrameSource.new(config: config, frame_rate: 30)
      frame_source.start

      frame = frame_source.capture

      expect(frame[:scene_name]).to eq("drop")
      expect(frame.dig(:scene, :layers, 0, :name)).to eq("drop_layer")
    ensure
      frame_source&.stop
    end
  end

  it "replays cached feature frames during offline rendering" do
    Dir.mktmpdir("vizcore-frame-source-feature-cache") do |dir|
      scene_path = File.join(dir, "scene.rb")
      audio_file = Vizcore.root.join("spec", "fixtures", "audio", "kick_120bpm.wav")
      feature_file = File.join(dir, "features.json")
      File.write(
        scene_path,
        "Vizcore.define { scene(:basic) { layer(:core) { type :geometry } } }"
      )
      File.write(
        feature_file,
        JSON.generate(
          {
            "version" => Vizcore::Analysis::FeatureRecorder::VERSION,
            "metadata" => {
              "frames" => 2,
              "fps" => 30.0,
              "sample_rate" => 30_720,
              "capture_size" => 1024
            },
            "features" => [
              {
                "index" => 0,
                "time" => 0.0,
                "audio" => {
                  "amplitude" => 0.2,
                  "bands" => {},
                  "beat" => false,
                  "beat_count" => 1
                }
              },
              {
                "index" => 1,
                "time" => 0.033,
                "audio" => {
                  "amplitude" => 0.4,
                  "bands" => {},
                  "beat" => true,
                  "beat_count" => 2
                }
              }
            ]
          }
        )
      )

      config = Vizcore::Config.new(
        scene_file: scene_path,
        audio_source: :file,
        audio_file: audio_file,
        feature_file: feature_file
      )
      frame_source = Vizcore::Renderer::SceneFrameSource.new(config: config, frame_rate: 30)
      frame_source.start

      first = frame_source.capture
      second = frame_source.capture

      expect(first[:audio][:amplitude]).to eq(0.2)
      expect(second[:audio][:amplitude]).to eq(0.4)
      expect(first[:audio][:beat_count]).to eq(1)
      expect(second[:audio][:beat_count]).to eq(2)
      expect(first[:scene_name]).to eq("basic")
      expect(second[:scene_name]).to eq("basic")
    ensure
      frame_source&.stop
    end
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
