# frozen_string_literal: true

require "vizcore/analysis/fft_processor"

RSpec.describe Vizcore::Analysis::FFTProcessor do
  def sine_samples(frequency_hz:, sample_rate:, count:, amplitude: 1.0)
    step = 2.0 * Math::PI * frequency_hz / sample_rate.to_f
    Array.new(count) { |index| Math.sin(step * index) * amplitude }
  end

  it "detects the peak bin near a 440Hz sine wave" do
    processor = described_class.new(sample_rate: 44_100, fft_size: 1024, window: :hamming)
    samples = sine_samples(frequency_hz: 440.0, sample_rate: 44_100, count: 1024)

    result = processor.call(samples)
    expected_bin = (440.0 * 1024 / 44_100).round
    bin_width_hz = 44_100.0 / 1024.0

    expect(result[:peak_bin]).to be_between(expected_bin - 1, expected_bin + 1)
    expect(result[:peak_frequency]).to be_within(bin_width_hz).of(440.0)
    expect(result[:magnitudes].length).to eq(512)
  end

  it "supports multiple window functions" do
    samples = sine_samples(frequency_hz: 220.0, sample_rate: 44_100, count: 1024)

    %i[none hamming hann blackman].each do |window|
      processor = described_class.new(sample_rate: 44_100, fft_size: 1024, window: window)
      result = processor.call(samples)
      expect(result[:peak_bin]).to be > 0
    end
  end

  it "uses the ruby backend when explicitly requested" do
    processor = described_class.new(sample_rate: 44_100, fft_size: 1024, backend: :ruby)

    expect(processor.backend_name).to eq(:ruby)
  end

  it "falls back to ruby backend for auto when fftw is unavailable" do
    allow(described_class).to receive(:fftw_available?).and_return(false)
    processor = described_class.new(sample_rate: 44_100, fft_size: 1024, backend: :auto)

    expect(processor.backend_name).to eq(:ruby)
    result = processor.call(sine_samples(frequency_hz: 220.0, sample_rate: 44_100, count: 1024))
    expect(result[:peak_bin]).to be > 0
  end

  it "raises when fftw backend is explicitly selected but unavailable" do
    allow(described_class).to receive(:fftw_available?).and_return(false)

    expect do
      described_class.new(backend: :fftw)
    end.to raise_error(ArgumentError, /fftw backend is unavailable/)
  end

  it "raises for unsupported window" do
    expect do
      described_class.new(window: :invalid)
    end.to raise_error(ArgumentError)
  end

  it "raises for unsupported backend" do
    expect do
      described_class.new(backend: :invalid)
    end.to raise_error(ArgumentError, /unsupported backend/)
  end
end
