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

    expect(result).to include(:amplitude, :bands, :fft, :onset, :onsets, :drums, :beat, :beat_confidence, :beat_pulse, :beat_count, :bpm, :peak_frequency)
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
    expect(result[:beat_confidence]).to eq(0.0)
    expect(result[:beat_pulse]).to eq(0.0)
    expect(result[:onset]).to eq(0.0)
    expect(result[:onsets]).to eq(sub: 0.0, low: 0.0, mid: 0.0, high: 0.0)
    expect(result[:drums]).to eq(kick: 0.0, snare: 0.0, hihat: 0.0)
    expect(result[:bpm]).to eq(0.0)
    expect(result[:peak_frequency]).to eq(0.0)
  end

  it "suppresses beats and bpm while input is below the silence floor" do
    beat_detector = instance_double(
      Vizcore::Analysis::BeatDetector,
      call: { beat: true, beat_count: 4, instant_energy: 0.0, average_energy: 0.0, threshold: 0.0 }
    )
    bpm_estimator = instance_double(Vizcore::Analysis::BPMEstimator)
    allow(bpm_estimator).to receive(:reset)
    allow(bpm_estimator).to receive(:call)

    pipeline = described_class.new(
      sample_rate: 44_100,
      fft_size: 1024,
      beat_detector: beat_detector,
      bpm_estimator: bpm_estimator
    )
    samples = Array.new(1024, 0.001)

    result = pipeline.call(samples)

    expect(result[:beat]).to eq(false)
    expect(result[:beat_confidence]).to eq(0.0)
    expect(result[:beat_pulse]).to eq(0.0)
    expect(result[:onset]).to eq(0.0)
    expect(result[:bpm]).to eq(0.0)
    expect(beat_detector).to have_received(:call)
    expect(bpm_estimator).to have_received(:call).with(beat: false)

    described_class::SILENCE_RESET_FRAMES.times { pipeline.call(samples) }
    expect(bpm_estimator).to have_received(:reset)
  end

  it "feeds gated silent frames to beat history for percussive onsets" do
    beat_detector = Vizcore::Analysis::BeatDetector.new(
      history_size: 8,
      sensitivity: 1.25,
      refractory_frames: 1,
      min_history: 4
    )
    pipeline = described_class.new(
      sample_rate: 44_100,
      fft_size: 1024,
      beat_detector: beat_detector,
      noise_gate: 0.01
    )
    kick = Array.new(1024, 0.8)
    silence = Array.new(1024, 0.0)

    pipeline.call(kick)
    4.times { pipeline.call(silence) }
    result = pipeline.call(kick)

    expect(result[:beat]).to eq(true)
  end

  it "reports beat confidence from detector energy ratio" do
    beat_detector = instance_double(
      Vizcore::Analysis::BeatDetector,
      call: { beat: false, beat_count: 0, instant_energy: 0.2, average_energy: 0.3, threshold: 0.4 }
    )
    pipeline = described_class.new(sample_rate: 44_100, fft_size: 1024, beat_detector: beat_detector)
    samples = sine_samples(frequency_hz: 220.0, sample_rate: 44_100, count: 1024, amplitude: 0.6)

    result = pipeline.call(samples)

    expect(result[:beat]).to eq(false)
    expect(result[:beat_confidence]).to eq(0.5)
  end

  it "reports positive onset deltas for amplitude and bands" do
    pipeline = described_class.new(sample_rate: 44_100, fft_size: 1024)
    quiet = sine_samples(frequency_hz: 180.0, sample_rate: 44_100, count: 1024, amplitude: 0.2)
    loud = sine_samples(frequency_hz: 180.0, sample_rate: 44_100, count: 1024, amplitude: 0.8)

    pipeline.call(quiet)
    result = pipeline.call(loud)

    expect(result[:onset]).to be > 0.0
    expect(result[:onsets].fetch(:low)).to be >= 0.0
  end

  it "reports simple drum confidence from band onsets" do
    pipeline = described_class.new(sample_rate: 44_100, fft_size: 1024)
    silence = Array.new(1024, 0.0)
    kick = sine_samples(frequency_hz: 90.0, sample_rate: 44_100, count: 1024, amplitude: 0.9)

    pipeline.call(silence)
    result = pipeline.call(kick)

    expect(result[:drums].fetch(:kick)).to be > 0.0
    expect(result[:drums].fetch(:snare)).to be >= 0.0
    expect(result[:drums].fetch(:hihat)).to be >= 0.0
  end

  it "can adaptively normalize feature levels when enabled" do
    smoother = instance_double(Vizcore::Analysis::Smoother)
    allow(smoother).to receive(:smooth) { |_key, value, **_opts| value }
    allow(smoother).to receive(:smooth_hash) { |hash, **_opts| hash }
    allow(smoother).to receive(:smooth_array) { |array, **_opts| array }

    pipeline = described_class.new(
      sample_rate: 44_100,
      fft_size: 1024,
      smoother: smoother,
      audio_normalize: { mode: :adaptive, window_size: 4, target: 0.8, floor: 0.05 }
    )
    samples = Array.new(1024, 0.2)

    result = pipeline.call(samples)

    expect(result[:amplitude]).to eq(0.8)
    expect(result[:fft].max).to be <= 1.0
  end

  it "keeps intentional microphone-level input above the noise gate active" do
    pipeline = described_class.new(sample_rate: 44_100, fft_size: 1024)
    samples = sine_samples(frequency_hz: 180.0, sample_rate: 44_100, count: 1024, amplitude: 0.03)

    result = pipeline.call(samples)

    expect(result[:amplitude]).to be > 0.0
    expect(result[:bands].values.sum).to be > 0.0
    expect(result[:fft].sum).to be > 0.0
  end

  it "can lower the noise gate for quiet inputs" do
    pipeline = described_class.new(sample_rate: 44_100, fft_size: 1024, noise_gate: 0.0001)
    samples = sine_samples(frequency_hz: 180.0, sample_rate: 44_100, count: 1024, amplitude: 0.0004)

    result = pipeline.call(samples)

    expect(result[:amplitude]).to be > 0.0
  end

  it "clears smoothed band and spectrum values during silence" do
    pipeline = described_class.new(sample_rate: 44_100, fft_size: 1024)
    active_samples = sine_samples(frequency_hz: 80.0, sample_rate: 44_100, count: 1024, amplitude: 0.8)
    silent_samples = Array.new(1024, 0.0)

    active = pipeline.call(active_samples)
    silent = pipeline.call(silent_samples)

    expect(active[:bands].values.sum).to be > 0.0
    expect(active[:fft].sum).to be > 0.0
    expect(silent[:amplitude]).to eq(0.0)
    expect(silent[:bands]).to eq(sub: 0.0, low: 0.0, mid: 0.0, high: 0.0)
    expect(silent[:fft]).to eq(Array.new(32, 0.0))
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
    expect(result[:beat_confidence]).to eq(1.0)
    expect(result[:beat_pulse]).to eq(1.0)
    expect(result[:bpm]).to eq(126.5)
  end

  it "emits a decaying beat pulse" do
    beat_detector = instance_double(Vizcore::Analysis::BeatDetector)
    allow(beat_detector).to receive(:call).and_return(
      { beat: true, beat_count: 1 },
      { beat: false, beat_count: 1 }
    )

    pipeline = described_class.new(sample_rate: 44_100, fft_size: 1024, beat_detector: beat_detector)
    samples = sine_samples(frequency_hz: 220.0, sample_rate: 44_100, count: 1024, amplitude: 0.6)

    first = pipeline.call(samples)
    second = pipeline.call(samples)

    expect(first[:beat_pulse]).to eq(1.0)
    expect(second[:beat_pulse]).to be_between(0.0, 1.0).exclusive
  end
end
