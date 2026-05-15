# frozen_string_literal: true

require "json"
require "tmpdir"
require "vizcore/analysis/feature_recorder"

RSpec.describe Vizcore::Analysis::FeatureRecorder do
  it "writes feature frames for an audio file" do
    Dir.mktmpdir("vizcore-feature-recorder") do |dir|
      audio_file = Vizcore.root.join("spec", "fixtures", "audio", "kick_120bpm.wav")
      out = File.join(dir, "features.json")

      result = described_class.new(audio_file: audio_file, frames: 3, fps: 30, noise_gate: 0.0).write(out: out)
      payload = JSON.parse(File.read(out))

      expect(result).to include(path: Pathname.new(out).expand_path, frames: 3, fps: 30.0, sample_rate: 30_720)
      expect(payload.fetch("version")).to eq("vizcore.features.v1")
      expect(payload.dig("metadata", "audio_file")).to eq(audio_file.to_s)
      expect(payload.dig("metadata", "capture_size")).to eq(1024)
      expect(payload.fetch("features").length).to eq(3)
      expect(payload.dig("features", 0, "audio")).to include(
        "amplitude",
        "bands",
        "fft",
        "beat",
        "beat_confidence",
        "bpm"
      )
    end
  end

  it "raises for missing audio files" do
    expect do
      described_class.new(audio_file: "missing.wav", frames: 1).write(out: "features.json")
    end.to raise_error(ArgumentError, /Audio file not found/)
  end
end
