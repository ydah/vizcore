# frozen_string_literal: true

require "vizcore/analysis/band_splitter"

RSpec.describe Vizcore::Analysis::BandSplitter do
  it "extracts band energies based on frequency ranges" do
    splitter = described_class.new(sample_rate: 44_100, fft_size: 1024)
    magnitudes = Array.new(512, 0.0)

    low_bin = (100.0 * 1024 / 44_100).round
    mid_bin = (1_000.0 * 1024 / 44_100).round
    high_bin = (8_000.0 * 1024 / 44_100).round
    magnitudes[low_bin] = 1.0
    magnitudes[mid_bin] = 0.6
    magnitudes[high_bin] = 0.25

    bands = splitter.call(magnitudes)

    expect(bands[:low]).to be > bands[:high]
    expect(bands[:mid]).to be > 0.0
    expect(bands[:sub]).to be_between(0.0, 1.0)
    expect(bands[:high]).to be_between(0.0, 1.0)
  end

  it "returns zeros when magnitudes are empty" do
    splitter = described_class.new
    bands = splitter.call([])

    expect(bands).to eq(sub: 0.0, low: 0.0, mid: 0.0, high: 0.0)
  end
end
