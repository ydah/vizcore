# frozen_string_literal: true

require "vizcore/analysis/bpm_estimator"

RSpec.describe Vizcore::Analysis::BPMEstimator do
  it "estimates bpm close to 120 for periodic beat impulses" do
    estimator = described_class.new(
      frame_rate: 30.0,
      min_bpm: 80.0,
      max_bpm: 180.0,
      history_seconds: 12.0,
      smoothing: 0.4,
      min_onsets: 4
    )

    # 120 BPM at 30 fps => one beat every 15 frames
    bpm = 0.0
    360.times do |frame_index|
      beat = (frame_index % 15).zero?
      bpm = estimator.call(beat: beat)
    end

    expect(bpm).to be_within(2.0).of(120.0)
  end

  it "keeps the previous estimate when no additional beats are detected" do
    estimator = described_class.new(frame_rate: 30.0, history_seconds: 8.0, min_onsets: 4, smoothing: 1.0)

    240.times do |frame_index|
      estimator.call(beat: (frame_index % 15).zero?)
    end
    established = estimator.call(beat: false)

    60.times { estimator.call(beat: false) }
    after_silence = estimator.call(beat: false)

    expect(established).to be > 0.0
    expect(after_silence).to be_within(0.01).of(established)
  end

  it "returns zero when there is insufficient beat history" do
    estimator = described_class.new(frame_rate: 30.0, min_onsets: 6)

    20.times { estimator.call(beat: false) }

    expect(estimator.call(beat: true)).to eq(0.0)
  end
end
