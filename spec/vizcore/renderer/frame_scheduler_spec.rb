# frozen_string_literal: true

require "vizcore/renderer/frame_scheduler"

RSpec.describe Vizcore::Renderer::FrameScheduler do
  describe "#start / #stop" do
    it "ticks repeatedly until stopped" do
      timeline = [
        0.0,
        0.005, 0.007,
        0.021, 0.024,
        0.038, 0.041
      ]
      current_time = 0.0
      monotonic_clock = lambda do
        current_time = if timeline.empty?
                         current_time + 0.01
                       else
                         timeline.shift
                       end
      end
      sleep_calls = []

      scheduler = nil
      ticks = []
      scheduler = described_class.new(
        frame_rate: 60.0,
        monotonic_clock: monotonic_clock,
        sleeper: ->(seconds) { sleep_calls << seconds }
      ) do |elapsed|
        ticks << elapsed
        scheduler.stop if ticks.length >= 3
      end

      scheduler.start
      100.times do
        break unless scheduler.running?

        sleep(0.001)
      end

      expect(ticks.length).to eq(3)
      expect(ticks[0]).to be_within(0.0001).of(0.005)
      expect(ticks[1]).to be_within(0.0001).of(0.021)
      expect(ticks[2]).to be_within(0.0001).of(0.038)
      expect(sleep_calls).to all(be > 0.0)
      expect(scheduler.running?).to eq(false)
    end

    it "raises when frame rate is invalid" do
      expect { described_class.new(frame_rate: 0.0) }.to raise_error(ArgumentError, /frame_rate/)
    end
  end
end
