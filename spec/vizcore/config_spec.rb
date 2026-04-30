# frozen_string_literal: true

require "vizcore/config"

RSpec.describe Vizcore::Config do
  let(:scene_file) { Vizcore.root.join("examples", "basic.rb").to_s }

  it "parses audio source and optional audio file" do
    config = described_class.new(
      scene_file: scene_file,
      audio_source: "file",
      audio_file: "spec/fixtures/audio/pulse16_mono.wav"
    )

    expect(config.audio_source).to eq(:file)
    expect(config.audio_file).to be_a(Pathname)
    expect(config.audio_file.to_s).to end_with("spec/fixtures/audio/pulse16_mono.wav")
  end

  it "parses optional audio device" do
    config = described_class.new(scene_file: scene_file, audio_device: "5")

    expect(config.audio_device).to eq("5")
  end

  it "parses optional noise gate" do
    config = described_class.new(scene_file: scene_file, noise_gate: "0.03")

    expect(config.noise_gate).to eq(0.03)
  end

  it "raises for unsupported audio source" do
    expect do
      described_class.new(scene_file: scene_file, audio_source: "invalid")
    end.to raise_error(ArgumentError, /Unsupported audio source/)
  end
end
