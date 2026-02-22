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
        latest_samples: Array.new(1024, 0.0),
        realtime_capture_size: 735,
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
        latest_samples: Array.new(1024, 0.0),
        realtime_capture_size: 735,
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
          glsl: "shaders/custom_wave.frag",
          glsl_source: "void main() { }",
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
      expect(layer[:glsl]).to eq("shaders/custom_wave.frag")
      expect(layer[:glsl_source]).to eq("void main() { }")
      expect(layer[:params]).to include(intensity: 0.8, flash: true)
    end

    it "uses updated scene definition after hot reload" do
      input_manager = instance_double(
        Vizcore::Audio::InputManager,
        frame_size: 1024,
        sample_rate: 44_100,
        capture_frame: Array.new(1024, 0.0),
        latest_samples: Array.new(1024, 0.0),
        realtime_capture_size: 735,
        start: nil,
        stop: nil
      )
      analyzed = {
        amplitude: 0.5,
        bands: { sub: 0.0, low: 0.2, mid: 0.3, high: 0.4 },
        fft: Array.new(32, 0.1),
        beat: false,
        beat_count: 0,
        bpm: 0.0
      }
      pipeline = instance_double(Vizcore::Analysis::Pipeline, call: analyzed)
      broadcaster = described_class.new(
        scene_name: "intro",
        scene_layers: [{ name: :intro_layer, type: :geometry, params: {} }],
        input_manager: input_manager,
        analysis_pipeline: pipeline
      )

      broadcaster.update_scene(
        scene_name: :drop,
        scene_layers: [{ name: :drop_layer, type: :shader, shader: :gradient_pulse, params: {} }]
      )
      frame = broadcaster.build_frame(0.5, Array.new(1024, 0.0))

      expect(frame.dig(:scene, :name)).to eq("drop")
      expect(frame.dig(:scene, :layers, 0, :name)).to eq("drop_layer")
      expect(frame.dig(:scene, :layers, 0, :type)).to eq("shader")
    end

    it "reports audio capture errors and falls back to silence frame" do
      input_manager = instance_double(
        Vizcore::Audio::InputManager,
        frame_size: 1024,
        sample_rate: 44_100,
        latest_samples: Array.new(1024, 0.0),
        realtime_capture_size: 735,
        start: nil,
        stop: nil
      )
      allow(input_manager).to receive(:capture_frame).and_raise(StandardError.new("device busy"))
      reports = []
      broadcaster = described_class.new(
        scene_name: "basic",
        input_manager: input_manager,
        error_reporter: ->(message) { reports << message }
      )

      frame = broadcaster.build_frame(0.2)

      expect(frame.dig(:audio, :fft)).to be_a(Array)
      expect(frame.dig(:audio, :fft).length).to eq(32)
      expect(reports.join("\n")).to include("audio capture failed")
      expect(broadcaster.last_error).to be_a(StandardError)
    end
  end

  describe "#tick" do
    it "broadcasts scene_change when a transition condition is met" do
      input_manager = instance_double(
        Vizcore::Audio::InputManager,
        frame_size: 1024,
        sample_rate: 44_100,
        capture_frame: Array.new(1024, 0.0),
        latest_samples: Array.new(1024, 0.0),
        realtime_capture_size: 735,
        start: nil,
        stop: nil
      )
      pipeline = instance_double(
        Vizcore::Analysis::Pipeline,
        call: {
          amplitude: 0.7,
          bands: { sub: 0.1, low: 0.9, mid: 0.2, high: 0.1 },
          fft: Array.new(32, 0.05),
          beat: true,
          beat_count: 64,
          bpm: 128.0
        }
      )
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)

      broadcaster = described_class.new(
        scene_name: "intro",
        scene_layers: [{ name: :intro_layer, type: :geometry, params: {} }],
        scene_catalog: [
          { name: :intro, layers: [{ name: :intro_layer, type: :geometry, params: {} }] },
          { name: :drop, layers: [{ name: :drop_layer, type: :shader, params: {} }] }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc { beat_count >= 64 },
            effect: { name: :crossfade, options: { duration: 2.0 } }
          }
        ],
        input_manager: input_manager,
        analysis_pipeline: pipeline
      )

      broadcaster.tick(0.5, Array.new(1024, 0.0))
      next_frame = broadcaster.build_frame(0.6, Array.new(1024, 0.0))

      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "scene_change",
        payload: {
          from: "intro",
          to: "drop",
          effect: { name: :crossfade, options: { duration: 2.0 } }
        }
      )
      expect(next_frame.dig(:scene, :name)).to eq("drop")
    end

    it "captures approximately real-time sample count before analyzing latest frame window" do
      input_manager = instance_double(
        Vizcore::Audio::InputManager,
        frame_size: 1024,
        sample_rate: 44_100,
        start: nil,
        stop: nil
      )
      allow(input_manager).to receive(:realtime_capture_size).with(60.0).and_return(735)
      allow(input_manager).to receive(:capture_frame).with(735).and_return(Array.new(735, 0.1))
      allow(input_manager).to receive(:latest_samples).with(1024).and_return(Array.new(1024, 0.2))

      pipeline = instance_double(
        Vizcore::Analysis::Pipeline,
        call: {
          amplitude: 0.2,
          bands: { sub: 0.0, low: 0.1, mid: 0.2, high: 0.3 },
          fft: Array.new(32, 0.01),
          beat: false,
          beat_count: 0,
          bpm: 120.0
        }
      )

      frame = described_class.new(
        scene_name: "groove",
        input_manager: input_manager,
        analysis_pipeline: pipeline
      ).build_frame(0.1)

      expect(input_manager).to have_received(:capture_frame).with(735)
      expect(input_manager).to have_received(:latest_samples).with(1024)
      expect(frame.dig(:audio, :amplitude)).to eq(0.2)
    end
  end
end
