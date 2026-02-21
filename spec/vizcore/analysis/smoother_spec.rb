# frozen_string_literal: true

require "vizcore/analysis/smoother"

RSpec.describe Vizcore::Analysis::Smoother do
  it "applies exponential moving average for scalar values" do
    smoother = described_class.new(alpha: 0.5)

    first = smoother.smooth(:amplitude, 0.0)
    second = smoother.smooth(:amplitude, 1.0)
    third = smoother.smooth(:amplitude, 1.0)

    expect(first).to eq(0.0)
    expect(second).to eq(0.5)
    expect(third).to eq(0.75)
  end

  it "smooths hash values per key" do
    smoother = described_class.new(alpha: 0.5)

    first = smoother.smooth_hash({ low: 0.0, high: 1.0 }, namespace: :bands)
    second = smoother.smooth_hash({ low: 1.0, high: 0.0 }, namespace: :bands)

    expect(first).to eq(low: 0.0, high: 1.0)
    expect(second[:low]).to eq(0.5)
    expect(second[:high]).to eq(0.5)
  end

  it "smooths array values per index" do
    smoother = described_class.new(alpha: 0.25)

    first = smoother.smooth_array([0.0, 1.0], namespace: :fft)
    second = smoother.smooth_array([1.0, 0.0], namespace: :fft)

    expect(first).to eq([0.0, 1.0])
    expect(second[0]).to eq(0.25)
    expect(second[1]).to eq(0.75)
  end

  it "resets namespace-specific state" do
    smoother = described_class.new(alpha: 0.5)
    smoother.smooth_array([1.0], namespace: :fft)
    smoother.smooth(:amplitude, 1.0)

    smoother.reset(:fft)
    fft_after_reset = smoother.smooth_array([0.0], namespace: :fft)
    amplitude_after_reset = smoother.smooth(:amplitude, 0.0)

    expect(fft_after_reset).to eq([0.0])
    expect(amplitude_after_reset).to eq(0.5)
  end
end
