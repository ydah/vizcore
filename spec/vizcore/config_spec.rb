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

  it "raises for unsupported audio source" do
    expect do
      described_class.new(scene_file: scene_file, audio_source: "invalid")
    end.to raise_error(ArgumentError, /Unsupported audio source/)
  end
end
