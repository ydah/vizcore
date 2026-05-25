# frozen_string_literal: true

require "json"
require "pathname"
require "tmpdir"
require "vizcore/analysis/feature_replay"

RSpec.describe Vizcore::Analysis::FeatureReplay do
  def write_feature_file(dir, payload)
    path = Pathname.new(dir).join("features.json")
    path.write(JSON.generate(payload))
    path
  end

  let(:payload) do
    {
      "version" => Vizcore::Analysis::FeatureRecorder::VERSION,
      "metadata" => {
        "frames" => 2,
        "fps" => 30.0
      },
      "features" => [
        {
          "index" => 0,
          "audio" => {
            "amplitude" => 0.25,
            "bands" => { "sub" => 0.4, "low" => 0.3 },
            "fft" => [0.1, 0.2],
            "beat" => false
          }
        },
        {
          "index" => 1,
          "audio" => {
            "amplitude" => 0.75,
            "bands" => { "sub" => 0.8, "low" => 0.2 },
            "fft" => [0.3, 0.4],
            "beat" => true
          }
        }
      ]
    }
  end

  it "returns symbolized audio frames sequentially and loops" do
    Dir.mktmpdir("vizcore-feature-replay") do |dir|
      replay = described_class.new(path: write_feature_file(dir, payload))

      first = replay.call
      first[:bands][:sub] = 1.0

      expect(first).to include(amplitude: 0.25, bands: include(sub: 1.0), beat: false)
      expect(replay.call).to include(amplitude: 0.75, bands: include(sub: 0.8), beat: true)
      expect(replay.call).to include(amplitude: 0.25, bands: include(sub: 0.4), beat: false)
      expect(replay.metadata).to include(frames: 2, fps: 30.0)
      expect(replay.frame_count).to eq(2)
      expect(replay.cursor).to eq(1)
    end
  end

  it "seeks by frame index and timestamp without mutating random frame reads" do
    Dir.mktmpdir("vizcore-feature-replay") do |dir|
      replay = described_class.new(path: write_feature_file(dir, payload))

      expect(replay.seek(1).call).to include(amplitude: 0.75)
      expect(replay.seek(4).call).to include(amplitude: 0.25)

      replay.seek_seconds(1.0 / 30.0)
      expect(replay.call).to include(amplitude: 0.75)

      expect(replay.frame(0)).to include(amplitude: 0.25)
      expect(replay.cursor).to eq(0)
    end
  end

  it "rejects unsupported versions" do
    Dir.mktmpdir("vizcore-feature-replay") do |dir|
      path = write_feature_file(dir, payload.merge("version" => "old"))

      expect { described_class.new(path: path) }.to raise_error(ArgumentError, /Unsupported feature file version/)
    end
  end

  it "rejects feature files with no frames" do
    Dir.mktmpdir("vizcore-feature-replay") do |dir|
      path = write_feature_file(dir, payload.merge("features" => []))

      expect { described_class.new(path: path) }.to raise_error(ArgumentError, /contains no frames/)
    end
  end
end
