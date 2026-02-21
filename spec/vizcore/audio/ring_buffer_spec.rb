# frozen_string_literal: true

require "vizcore/audio/ring_buffer"

RSpec.describe Vizcore::Audio::RingBuffer do
  describe "#write" do
    it "keeps only the latest values up to capacity" do
      buffer = described_class.new(4)

      buffer.write([1, 2, 3, 4, 5, 6])

      expect(buffer.size).to eq(4)
      expect(buffer.latest).to eq([3.0, 4.0, 5.0, 6.0])
    end

    it "accepts values that respond to numeric coercion" do
      buffer = described_class.new(3)

      buffer.write(["1.25", 2, 3.5])

      expect(buffer.latest).to eq([1.25, 2.0, 3.5])
    end
  end

  describe "#latest" do
    it "returns a subset from the most recent samples" do
      buffer = described_class.new(5)
      buffer.write([10, 20, 30, 40, 50])

      expect(buffer.latest(2)).to eq([40.0, 50.0])
      expect(buffer.latest(10)).to eq([10.0, 20.0, 30.0, 40.0, 50.0])
    end

    it "returns an empty array for zero or negative size requests" do
      buffer = described_class.new(3)
      buffer.write([1, 2, 3])

      expect(buffer.latest(0)).to eq([])
      expect(buffer.latest(-1)).to eq([])
    end
  end

  describe "#clear" do
    it "removes all buffered samples" do
      buffer = described_class.new(3)
      buffer.write([1, 2, 3])

      buffer.clear

      expect(buffer.size).to eq(0)
      expect(buffer.latest).to eq([])
    end
  end

  it "raises for invalid capacity" do
    expect { described_class.new(0) }.to raise_error(ArgumentError)
  end

  it "raises when non-numeric samples are written" do
    buffer = described_class.new(2)
    expect { buffer.write([1, Object.new]) }.to raise_error(ArgumentError)
  end
end
