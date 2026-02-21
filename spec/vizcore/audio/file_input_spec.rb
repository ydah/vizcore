# frozen_string_literal: true

require "vizcore/audio/file_input"

RSpec.describe Vizcore::Audio::FileInput do
  let(:fixture_path) { Vizcore.root.join("spec", "fixtures", "audio", "pulse16_mono.wav").to_s }
  let(:expected_sequence) { [0.0, 12_000.0, -12_000.0, 24_000.0, -24_000.0, 0.0, 8_000.0, -8_000.0] }

  it "reads samples from a WAV fixture file" do
    input = described_class.new(path: fixture_path)
    input.start

    expect(input.read(8)).to eq(expected_sequence)
  ensure
    input&.stop
  end

  it "loops over WAV samples when requested frames exceed fixture length" do
    input = described_class.new(path: fixture_path)
    input.start

    expect(input.read(10)).to eq(expected_sequence + [0.0, 12_000.0])
  ensure
    input&.stop
  end

  it "returns silence when not started" do
    input = described_class.new(path: fixture_path)
    expect(input.read(4)).to eq([0.0, 0.0, 0.0, 0.0])
  end
end
