# frozen_string_literal: true

require "vizcore/analysis/tap_tempo"

RSpec.describe Vizcore::Analysis::TapTempo do
  it "returns nil until two valid taps are available" do
    tap_tempo = described_class.new

    expect(tap_tempo.tap(timestamp_ms: 1_000.0)).to be_nil
    expect(tap_tempo.tap(timestamp_ms: 1_500.0)).to eq(120.0)
  end

  it "averages recent tap intervals" do
    tap_tempo = described_class.new(history_size: 2)

    tap_tempo.tap(timestamp_ms: 1_000.0)
    tap_tempo.tap(timestamp_ms: 1_500.0)
    bpm = tap_tempo.tap(timestamp_ms: 2_100.0)

    expect(bpm).to be_within(0.01).of(109.09)
  end

  it "resets after a stale gap" do
    tap_tempo = described_class.new(reset_after_ms: 1_000.0)

    tap_tempo.tap(timestamp_ms: 1_000.0)
    tap_tempo.tap(timestamp_ms: 1_500.0)

    expect(tap_tempo.tap(timestamp_ms: 3_000.0)).to be_nil
  end
end
