# frozen_string_literal: true

require "vizcore/analysis/adaptive_normalizer"

RSpec.describe Vizcore::Analysis::AdaptiveNormalizer do
  it "scales amplitude, bands, and fft against a rolling peak" do
    normalizer = described_class.new(window_size: 4, target: 0.8, floor: 0.05)

    result = normalizer.call(
      amplitude: 0.2,
      bands: { low: 0.1, mid: 0.3 },
      fft: [0.05, 0.25]
    )

    expect(result[:amplitude]).to eq(0.8)
    expect(result[:bands]).to eq(low: 0.4, mid: 1.0)
    expect(result[:fft]).to eq([0.2, 1.0])
    expect(result[:gain]).to eq(4.0)
  end

  it "uses the configured floor to avoid extreme gain for tiny signals" do
    normalizer = described_class.new(window_size: 4, target: 0.8, floor: 0.2)

    result = normalizer.call(amplitude: 0.01, bands: { low: 0.01 }, fft: [0.01])

    expect(result[:amplitude]).to eq(0.04)
    expect(result[:bands]).to eq(low: 0.04)
    expect(result[:fft]).to eq([0.04])
  end

  it "can normalize bands against independent rolling peaks" do
    normalizer = described_class.new(window_size: 4, target: 0.8, floor: 0.05, per_band: true)

    result = normalizer.call(
      amplitude: 0.2,
      bands: { low: 0.1, mid: 0.4 },
      fft: [0.1]
    )

    expect(result[:amplitude]).to eq(0.8)
    expect(result[:bands]).to eq(low: 0.8, mid: 0.8)
    expect(result[:fft]).to eq([0.4])
  end

  it "can leave band and fft ratios unamplified while normalizing amplitude" do
    normalizer = described_class.new(window_size: 4, target: 0.8, floor: 0.05, scale_bands: false, scale_fft: false)

    result = normalizer.call(
      amplitude: 0.2,
      bands: { low: 0.1, mid: 0.3 },
      fft: [0.05, 0.25]
    )

    expect(result[:amplitude]).to eq(0.8)
    expect(result[:bands]).to eq(low: 0.1, mid: 0.3)
    expect(result[:fft]).to eq([0.05, 0.25])
  end
end
