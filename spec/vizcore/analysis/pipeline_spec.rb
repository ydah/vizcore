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

  it "integrates bpm estimator and smoother in the output path" do
    beat_detector = instance_double(
      Vizcore::Analysis::BeatDetector,
      call: { beat: true, beat_count: 7, instant_energy: 0.9, average_energy: 0.2, threshold: 0.4 }
    )
    bpm_estimator = instance_double(Vizcore::Analysis::BPMEstimator)
    allow(bpm_estimator).to receive(:call).with(beat: true).and_return(126.5)

    smoother = instance_double(Vizcore::Analysis::Smoother)
    allow(smoother).to receive(:smooth) do |_key, value, **_opts|
      value
    end
    allow(smoother).to receive(:smooth_hash) do |hash, **_opts|
      hash
    end
    allow(smoother).to receive(:smooth_array) do |array, **_opts|
      array
    end

    pipeline = described_class.new(
      sample_rate: 44_100,
      fft_size: 1024,
      beat_detector: beat_detector,
      bpm_estimator: bpm_estimator,
      smoother: smoother
    )
    samples = sine_samples(frequency_hz: 220.0, sample_rate: 44_100, count: 1024, amplitude: 0.6)

    result = pipeline.call(samples)

    expect(bpm_estimator).to have_received(:call).with(beat: true)
    expect(smoother).to have_received(:smooth).with(:bpm, 126.5, alpha: 0.2)
    expect(result[:beat_count]).to eq(7)
    expect(result[:bpm]).to eq(126.5)
  end
end
