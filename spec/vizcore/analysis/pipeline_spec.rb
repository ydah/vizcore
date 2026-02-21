# frozen_string_literal: true

require "vizcore/analysis/pipeline"

RSpec.describe Vizcore::Analysis::Pipeline do
  def sine_samples(frequency_hz:, sample_rate:, count:, amplitude: 1.0)
    step = 2.0 * Math::PI * frequency_hz / sample_rate.to_f
    Array.new(count) { |index| Math.sin(step * index) * amplitude }
  end

  it "produces analysis payload with fft, bands and beat fields" do
    pipeline = described_class.new(sample_rate: 44_100, fft_size: 1024)
    samples = sine_samples(frequency_hz: 440.0, sample_rate: 44_100, count: 1024, amplitude: 0.8)

    result = pipeline.call(samples)

    expect(result).to include(:amplitude, :bands, :fft, :beat, :beat_count, :bpm, :peak_frequency)
    expect(result[:bands].keys).to contain_exactly(:sub, :low, :mid, :high)
    expect(result[:fft].length).to eq(32)
    expect(result[:peak_frequency]).to be_within(50.0).of(440.0)
    expect(result[:bpm]).to be_a(Float)
  end

  it "returns zeroed output for empty samples" do
    pipeline = described_class.new(sample_rate: 44_100, fft_size: 1024)
    result = pipeline.call([])

    expect(result[:amplitude]).to eq(0.0)
    expect(result[:bands]).to eq(sub: 0.0, low: 0.0, mid: 0.0, high: 0.0)
    expect(result[:fft]).to eq(Array.new(32, 0.0))
    expect(result[:bpm]).to be >= 0.0
  end
end
