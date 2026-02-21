# frozen_string_literal: true

require "vizcore/server/frame_broadcaster"

RSpec.describe Vizcore::Server::FrameBroadcaster do
  describe "#build_frame" do
    it "returns a frame payload compatible with frontend expectations" do
      frame = described_class.new(scene_name: "basic").build_frame(1.25)

      expect(frame).to include(:timestamp, :audio, :scene, :transition)
      expect(frame[:audio]).to include(:amplitude, :bands, :fft, :beat, :beat_count, :bpm)
      expect(frame[:scene]).to include(:name, :layers)
      expect(frame[:scene][:name]).to eq("basic")
      expect(frame[:audio][:fft].length).to eq(32)
    end
  end
end
