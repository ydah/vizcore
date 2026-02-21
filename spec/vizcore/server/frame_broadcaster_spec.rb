# frozen_string_literal: true

require "vizcore/server/frame_broadcaster"

RSpec.describe Vizcore::Server::FrameBroadcaster do
  describe "#start / #stop" do
    it "starts and stops input manager through frame scheduler lifecycle" do
      input_manager = instance_double(
        Vizcore::Audio::InputManager,
        frame_size: 1024,
        sample_rate: 44_100,
        capture_frame: Array.new(1024, 0.0),
        start: nil,
        stop: nil
      )
      scheduler = instance_double(Vizcore::Renderer::FrameScheduler, start: nil, stop: nil, running?: false)
      allow(scheduler).to receive(:running?).and_return(false, true)

      broadcaster = described_class.new(input_manager: input_manager, frame_scheduler: scheduler)
      broadcaster.start
      broadcaster.stop

      expect(input_manager).to have_received(:start)
      expect(scheduler).to have_received(:start)
      expect(scheduler).to have_received(:stop)
      expect(input_manager).to have_received(:stop)
    end
  end

  describe "#build_frame" do
    it "returns a frame payload compatible with frontend expectations" do
      frame = described_class.new(scene_name: "basic").build_frame(1.25)

      expect(frame).to include(:timestamp, :audio, :scene, :transition)
      expect(frame[:audio]).to include(:amplitude, :bands, :fft, :beat, :beat_count, :bpm)
      expect(frame[:scene]).to include(:name, :layers)
      expect(frame[:scene][:name]).to eq("basic")
      expect(frame[:audio][:fft].length).to eq(32)
    end

    it "builds scene layers from DSL definitions and mapping sources" do
      input_manager = instance_double(
        Vizcore::Audio::InputManager,
        frame_size: 1024,
        sample_rate: 44_100,
        capture_frame: Array.new(1024, 0.0),
        start: nil,
        stop: nil
      )
      analyzed = {
        amplitude: 0.8,
        bands: { sub: 0.1, low: 0.6, mid: 0.4, high: 0.2 },
        fft: Array.new(32, 0.05),
        beat: true,
        beat_count: 9,
        bpm: 126.0
      }
      pipeline = instance_double(Vizcore::Analysis::Pipeline, call: analyzed)
      layers = [
        {
          name: :background,
          type: :shader,
          shader: :gradient_pulse,
          params: { intensity: 0.1 },
          mappings: [
            { source: { kind: :amplitude }, target: :intensity },
            { source: { kind: :beat }, target: :flash }
          ]
        }
      ]

      frame = described_class.new(
        scene_name: "intro",
        scene_layers: layers,
        input_manager: input_manager,
        analysis_pipeline: pipeline
      ).build_frame(0.5, Array.new(1024, 0.0))

      layer = frame[:scene][:layers].first
      expect(layer[:name]).to eq("background")
      expect(layer[:type]).to eq("shader")
      expect(layer[:shader]).to eq("gradient_pulse")
      expect(layer[:params]).to include(intensity: 0.8, flash: true)
    end
  end
end
