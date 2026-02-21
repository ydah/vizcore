# frozen_string_literal: true

require "vizcore/analysis/beat_detector"

RSpec.describe Vizcore::Analysis::BeatDetector do
  def frame(amplitude, size = 1024)
    Array.new(size, amplitude)
  end

  it "detects beats using energy thresholding" do
    detector = described_class.new(history_size: 16, sensitivity: 1.4, refractory_frames: 2, min_history: 6)

    8.times { detector.call(frame(0.05)) }
    result = detector.call(frame(0.7))

    expect(result[:beat]).to eq(true)
    expect(result[:beat_count]).to eq(1)
  end

  it "applies refractory frames to avoid duplicate triggers" do
    detector = described_class.new(history_size: 16, sensitivity: 1.3, refractory_frames: 3, min_history: 6)

    8.times { detector.call(frame(0.05)) }
    first = detector.call(frame(0.8))
    second = detector.call(frame(0.75))
    detector.call(frame(0.05))
    third = detector.call(frame(0.8))

    expect(first[:beat]).to eq(true)
    expect(second[:beat]).to eq(false)
    expect(third[:beat]).to eq(false)
    expect(detector.beat_count).to eq(1)
  end
end
