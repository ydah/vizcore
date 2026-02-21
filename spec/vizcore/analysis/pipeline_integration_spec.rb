# frozen_string_literal: true

require "vizcore/analysis"
require "vizcore/audio/file_input"

RSpec.describe "Analysis pipeline integration with WAV fixture" do
  it "estimates bpm within ±2 for a known 120 BPM kick pattern" do
    fixture_path = Vizcore.root.join("spec", "fixtures", "audio", "kick_120bpm.wav").to_s
    frame_size = 1024
    sample_rate = 30_720

    input = Vizcore::Audio::FileInput.new(path: fixture_path, sample_rate: sample_rate)
    beat_detector = Vizcore::Analysis::BeatDetector.new(
      history_size: 32,
      sensitivity: 1.25,
      refractory_frames: 4,
      min_history: 8
    )
    bpm_estimator = Vizcore::Analysis::BPMEstimator.new(
      frame_rate: sample_rate.to_f / frame_size,
      min_bpm: 60.0,
      max_bpm: 180.0,
      history_seconds: 12.0,
      smoothing: 0.4,
      min_onsets: 4
    )
    pipeline = Vizcore::Analysis::Pipeline.new(
      sample_rate: sample_rate,
      fft_size: frame_size,
      beat_detector: beat_detector,
      bpm_estimator: bpm_estimator
    )

    input.start

    bpm = 0.0
    beat_count = 0
    360.times do
      result = pipeline.call(input.read(frame_size))
      bpm = result[:bpm]
      beat_count += 1 if result[:beat]
    end

    expect(beat_count).to be >= 16
    expect(bpm).to be_within(2.0).of(120.0)
  ensure
    input&.stop
  end
end
