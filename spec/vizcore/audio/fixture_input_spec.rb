# frozen_string_literal: true

require "vizcore/audio/fixture_input"

RSpec.describe Vizcore::Audio::FixtureInput do
  it "returns configured frames in order while running" do
    input = described_class.new(frames: [[0.1, 0.2], [0.3, 0.4]], sample_rate: 48_000)

    input.start

    expect(input.sample_rate).to eq(48_000)
    expect(input.read(2)).to eq([0.1, 0.2])
    expect(input.read(2)).to eq([0.3, 0.4])
  end

  it "loops frames by default" do
    input = described_class.new(frames: [[0.1], [0.2]])

    input.start

    expect(input.read(1)).to eq([0.1])
    expect(input.read(1)).to eq([0.2])
    expect(input.read(1)).to eq([0.1])
  end

  it "returns silence after the last frame when loop is disabled" do
    input = described_class.new(frames: [[0.5, 0.6]], loop: false)

    input.start

    expect(input.read(2)).to eq([0.5, 0.6])
    expect(input.read(2)).to eq([0.0, 0.0])
  end

  it "pads or trims frames to the requested size" do
    input = described_class.new(frames: [[0.1], [0.2, 0.3, 0.4]])

    input.start

    expect(input.read(3)).to eq([0.1, 0.0, 0.0])
    expect(input.read(2)).to eq([0.2, 0.3])
  end

  it "returns silence when stopped" do
    input = described_class.new(frames: [[0.7]])

    expect(input.read(2)).to eq([0.0, 0.0])
  end
end
