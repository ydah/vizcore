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

      expect(frame).to include(:timestamp, :audio, :scene, :transition, :metrics)
      expect(frame[:schema_version]).to eq("vizcore.frame.v1")
      expect(frame[:audio]).to include(:amplitude, :bands, :fft, :onset, :onsets, :drums, :beat, :beat_count, :bpm)
      expect(frame[:scene]).to include(:schema_version, :name, :layers)
      expect(frame[:scene][:schema_version]).to eq("vizcore.scene.v1")
      expect(frame[:scene_version]).to eq(frame.dig(:scene, :version))
      expect(frame[:metrics]).to include(
        :frame_id,
        :audio_capture_ms,
        :audio_analysis_ms,
        :scene_build_ms,
        :server_frame_ms
      )
      expect(frame[:scene][:name]).to eq("basic")
      expect(frame[:audio][:fft].length).to eq(32)
    end

    it "omits full scene when nothing changes in an unchanged scene frame" do
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
          amplitude: 0.2,
          bands: { sub: 0.0, low: 0.2, mid: 0.3, high: 0.4 },
          fft: Array.new(32, 0.12),
          beat: false,
          beat_count: 7,
          bpm: 120.0
        }
      )

      broadcaster = described_class.new(
        scene_name: :wire,
        scene_layers: [
          {
            name: :wire,
            type: :shader,
            params: { opacity: 0.3 },
            mappings: [{ source: { kind: :amplitude }, target: :opacity }]
          }
        ],
        input_manager: input_manager,
        analysis_pipeline: pipeline
      )

      first = broadcaster.build_frame(0.1, Array.new(1024, 0.0))
      second = broadcaster.build_frame(0.2, Array.new(1024, 0.0))

      expect(first).to have_key(:scene)
      expect(second).not_to have_key(:scene)
      expect(second[:scene_version]).to eq(first[:scene_version])
    end

    it "sends scene patch when only layer params change" do
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
          amplitude: 0.2,
          bands: { sub: 0.0, low: 0.2, mid: 0.3, high: 0.4 },
          fft: Array.new(32, 0.12),
          beat: false,
          beat_count: 7,
          bpm: 120.0
        }
      )

      broadcaster = described_class.new(
        scene_name: :wire,
        scene_layers: [
          {
            name: :wire,
            type: :shader,
            params: { opacity: 0.3 },
            mappings: [{ source: { kind: :amplitude }, target: :opacity }]
          }
        ],
        input_manager: input_manager,
        analysis_pipeline: pipeline
      )
      allow(pipeline).to receive(:call).and_return(
        {
          amplitude: 0.2,
          bands: { sub: 0.0, low: 0.2, mid: 0.3, high: 0.4 },
          fft: Array.new(32, 0.12),
          beat: false,
          beat_count: 7,
          bpm: 120.0
        },
        {
          amplitude: 0.6,
          bands: { sub: 0.0, low: 0.2, mid: 0.3, high: 0.4 },
          fft: Array.new(32, 0.12),
          beat: false,
          beat_count: 7,
          bpm: 120.0
        }
      )

      first_frame = broadcaster.build_frame(0.1, Array.new(1024, 0.0))
      second_frame = broadcaster.build_frame(0.2, Array.new(1024, 0.0))

      expect(first_frame).to have_key(:scene)
      expect(second_frame[:scene]).to include(
        patch: true,
        name: "wire",
        version: 1,
        layers: [{ index: 0, params: { opacity: 0.6 } }]
      );
      expect(second_frame[:scene_version]).to eq(1)
    end

    it "exposes runtime status after frame builds" do
      frame = described_class.new(scene_name: "basic").build_frame(1.25)
      broadcaster = described_class.new(scene_name: "status")

      broadcaster.build_frame(1.25)
      status = broadcaster.runtime_status

      expect(frame[:metrics]).to include(:server_frame_ms)
      expect(status).to include(
        current_scene: "status",
        fps: described_class::FRAME_RATE,
        frame_id: 0,
        websocket_clients: an_instance_of(Integer),
        dropped_frames: an_instance_of(Integer),
        websocket_backpressure: hash_including(
          :threshold_bytes,
          :active_clients,
          :total
        )
      )
      expect(status[:sample_rate]).to be_a(Integer)
      expect(status[:frame_size]).to be_a(Integer)
      expect(status[:input]).to include(
        source: "mic",
        ring_buffer: include(:capacity, :overrun_count, :underrun_count)
      )
      expect(status[:metrics]).to include(:server_frame_ms)
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

    it "applies custom shape param overrides to dynamic custom shapes" do
      shape_class = Class.new do
        include Vizcore::Shape

        param :radius, default: 10, min: 1, max: 200

        def draw(ctx)
          { kind: :circle, radius: ctx.param(:radius) }
        end
      end
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
        call: { amplitude: 0.0, bands: {}, fft: [], beat: false, beat_count: 0, bpm: 0.0 }
      )
      broadcaster = described_class.new(
        scene_name: "intro",
        scene_layers: [
          {
            name: :generated,
            type: :shape,
            params: {
              custom_shapes: [
                {
                  name: :dynamic_circle,
                  renderer: shape_class,
                  params: { radius: 10 },
                  param_schema: shape_class.shape_param_schema.values,
                  dynamic: true
                }
              ]
            }
          }
        ],
        input_manager: input_manager,
        analysis_pipeline: pipeline
      )

      broadcaster.set_custom_shape_param(layer_name: :generated, custom_shape_index: 0, param: :radius, value: 88)
      frame = broadcaster.build_frame(0.5, Array.new(1024, 0.0))

      layer = frame.dig(:scene, :layers, 0)
      expect(layer.dig(:params, :shapes)).to eq([{ kind: :circle, radius: 88.0 }])
      expect(layer.dig(:params, :custom_shape_controls)).to contain_exactly(
        hash_including(index: 0, name: "dynamic_circle", params: { radius: 88.0 }, shape_indices: [0])
      )
    end

    it "applies live layer parameter overrides" do
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
        call: { amplitude: 0.9, bands: {}, fft: [], beat: false, beat_count: 0, bpm: 0.0 }
      )
      broadcaster = described_class.new(
        scene_name: "intro",
        scene_layers: [
          {
            name: :rings,
            type: :shape,
            params: { opacity: 0.3 },
            mappings: [{ source: { kind: :amplitude }, target: :opacity }]
          }
        ],
        input_manager: input_manager,
        analysis_pipeline: pipeline
      )

      overrides = broadcaster.set_layer_param(layer_name: :rings, param: :opacity, value: 0.5)
      frame = broadcaster.build_frame(0.5, Array.new(1024, 0.0))

      expect(overrides).to eq("rings" => { "opacity" => 0.5 })
      expect(frame.dig(:scene, :layers, 0, :params, :opacity)).to eq(0.5)
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
      allow(input_manager).to receive(:capture_frame).with(any_args).and_return(Array.new(1024, 0.0))
      allow(input_manager).to receive(:capture_frame).and_raise(StandardError.new("device busy"))
      reports = []
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)
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
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "runtime_error",
        payload: hash_including(
          source: "runtime",
          context: "audio capture failed",
          event: "audio_capture_failed",
          message: /device busy/
        )
      )
    end

    it "includes runtime event when frame build fails" do
      input_manager = instance_double(
        Vizcore::Audio::InputManager,
        frame_size: 1024,
        sample_rate: 44_100,
        latest_samples: Array.new(1024, 0.0),
        realtime_capture_size: 735,
        start: nil,
        stop: nil
      )
      allow(input_manager).to receive(:capture_frame).with(any_args).and_return(Array.new(1024, 0.0))
      pipeline = instance_double(Vizcore::Analysis::Pipeline, call: {
        amplitude: 0.2,
        bands: { sub: 0.0, low: 0.0, mid: 0.0, high: 0.0 },
        fft: Array.new(32, 0.1),
        beat: false,
        beat_count: 0,
        bpm: 0.0
      })
      resolver = instance_double(
        Vizcore::DSL::MappingResolver,
        resolve_layers: nil
      )
      allow(resolver).to receive(:resolve_layers).and_raise(StandardError.new("mapping exploded"))

      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)

      broadcaster = described_class.new(
        scene_name: "intro",
        scene_layers: [
          {
            name: :rings,
            type: :shape,
            params: { opacity: 0.3 },
            mappings: [{ source: { kind: :amplitude }, target: :opacity }]
          }
        ],
        input_manager: input_manager,
        analysis_pipeline: pipeline,
        mapping_resolver: resolver
      )

      expect { broadcaster.build_frame(0.2) }.to raise_error(Vizcore::FrameBuildError)

      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "runtime_error",
        payload: hash_including(
          source: "runtime",
          event: "frame_build_failed",
          context: "frame build failed"
        )
      )
    end

    it "includes runtime event for transition trigger failures" do
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
          amplitude: 0.9,
          bands: { sub: 0.0, low: 0.4, mid: 0.3, high: 0.2 },
          fft: Array.new(32, 0.01),
          beat: true,
          beat_count: 1,
          bpm: 128.0
        }
      )
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)

      broadcaster = described_class.new(
        scene_name: :intro,
        scene_layers: [{ name: :intro_layer, type: :geometry, params: {} }],
        scene_catalog: [
          { name: :intro, layers: [{ name: :intro_layer, type: :geometry, params: {} }] },
          { name: :drop, layers: [{ name: :drop_layer, type: :shader, params: {} }] }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc { raise StandardError, "transition boom" }
          }
        ],
        input_manager: input_manager,
        analysis_pipeline: pipeline
      )

      broadcaster.tick(0.5, Array.new(1024, 0.0))

      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "runtime_error",
        payload: hash_including(
          source: "transition",
          event: "transition_failed",
          context: "transition trigger failed"
        )
      )
    end
  end

  describe "#tap_tempo" do
    it "locks the analysis pipeline after two taps" do
      pipeline = instance_double(Vizcore::Analysis::Pipeline, call: {})
      allow(pipeline).to receive(:bpm_lock=)

      broadcaster = described_class.new(analysis_pipeline: pipeline)

      expect(broadcaster.tap_tempo(timestamp_ms: 1_000.0)).to be_nil
      expect(broadcaster.tap_tempo(timestamp_ms: 1_500.0)).to eq(120.0)
      expect(pipeline).to have_received(:bpm_lock=).with({ bpm: 120.0, locked: true })
    end

    it "locks and unlocks BPM from external sync" do
      pipeline = instance_double(Vizcore::Analysis::Pipeline, call: {})
      allow(pipeline).to receive(:bpm_lock=)

      broadcaster = described_class.new(analysis_pipeline: pipeline)

      expect(broadcaster.lock_bpm(128)).to eq(128.0)
      expect(broadcaster.unlock_bpm).to eq(true)
      expect(pipeline).to have_received(:bpm_lock=).with({ bpm: 128.0, locked: true })
      expect(pipeline).to have_received(:bpm_lock=).with({ bpm: nil, locked: false })
    end
  end

  describe "#update_scene" do
    it "resets mapping resolver state when scene changes" do
      resolver = instance_double(Vizcore::DSL::MappingResolver)
      allow(resolver).to receive(:reset!)
      broadcaster = described_class.new(mapping_resolver: resolver)

      broadcaster.update_scene(scene_name: :drop, scene_layers: [])

      expect(resolver).to have_received(:reset!)
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
            trigger: proc { beat_count >= 1 },
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

    it "resets transition counters when a scene is reloaded" do
      input_manager = instance_double(
        Vizcore::Audio::InputManager,
        frame_size: 1024,
        sample_rate: 44_100,
        start: nil,
        stop: nil
      )
      pipeline = instance_double(Vizcore::Analysis::Pipeline)
      allow(pipeline).to receive(:call).and_return(
        {
          amplitude: 0.4,
          bands: { sub: 0.0, low: 0.3, mid: 0.2, high: 0.1 },
          fft: Array.new(32, 0.02),
          beat: true,
          beat_count: 1,
          bpm: 128.0
        },
        {
          amplitude: 0.4,
          bands: { sub: 0.0, low: 0.3, mid: 0.2, high: 0.1 },
          fft: Array.new(32, 0.02),
          beat: true,
          beat_count: 2,
          bpm: 128.0
        },
        {
          amplitude: 0.4,
          bands: { sub: 0.0, low: 0.3, mid: 0.2, high: 0.1 },
          fft: Array.new(32, 0.02),
          beat: true,
          beat_count: 10,
          bpm: 128.0
        },
        {
          amplitude: 0.4,
          bands: { sub: 0.0, low: 0.3, mid: 0.2, high: 0.1 },
          fft: Array.new(32, 0.02),
          beat: true,
          beat_count: 11,
          bpm: 128.0
        }
      )
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)

      intro_layers = [{ name: :intro_layer, type: :geometry, params: {} }]
      drop_layers = [{ name: :drop_layer, type: :shader, params: {} }]
      broadcaster = described_class.new(
        scene_name: "intro",
        scene_layers: intro_layers,
        scene_catalog: [
          { name: :intro, layers: intro_layers },
          { name: :drop, layers: drop_layers }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc { beat_count >= 2 && frame_count >= 2 },
            effect: { name: :crossfade, options: { duration: 1.0 } }
          }
        ],
        input_manager: input_manager,
        analysis_pipeline: pipeline
      )

      broadcaster.tick(0.1, Array.new(1024, 0.0))
      broadcaster.tick(0.2, Array.new(1024, 0.0))
      expect(broadcaster.current_scene_snapshot[:name]).to eq("drop")

      broadcaster.update_scene(scene_name: :intro, scene_layers: intro_layers)
      broadcaster.tick(0.3, Array.new(1024, 0.0))
      expect(broadcaster.current_scene_snapshot[:name]).to eq("intro")

      broadcaster.tick(0.4, Array.new(1024, 0.0))
      expect(broadcaster.current_scene_snapshot[:name]).to eq("drop")
    end

    it "evaluates transition seconds against scene-local elapsed time" do
      input_manager = instance_double(
        Vizcore::Audio::InputManager,
        frame_size: 1024,
        sample_rate: 44_100,
        start: nil,
        stop: nil
      )
      pipeline = instance_double(
        Vizcore::Analysis::Pipeline,
        call: {
          amplitude: 0.4,
          bands: { sub: 0.0, low: 0.3, mid: 0.2, high: 0.1 },
          fft: Array.new(32, 0.02),
          beat: false,
          beat_count: 0,
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
            trigger: proc { seconds >= 0.5 }
          }
        ],
        input_manager: input_manager,
        analysis_pipeline: pipeline
      )

      broadcaster.tick(10.0, Array.new(1024, 0.0))
      expect(broadcaster.current_scene_snapshot[:name]).to eq("intro")

      broadcaster.tick(10.5, Array.new(1024, 0.0))
      expect(broadcaster.current_scene_snapshot[:name]).to eq("drop")
    end

    it "does not evaluate transitions for file transport until playback starts" do
      input_manager = instance_double(
        Vizcore::Audio::InputManager,
        frame_size: 1024,
        sample_rate: 44_100,
        sync_transport: nil,
        start: nil,
        stop: nil
      )
      pipeline = instance_double(
        Vizcore::Analysis::Pipeline,
        call: {
          amplitude: 0.4,
          bands: { sub: 0.0, low: 0.8, mid: 0.3, high: 0.2 },
          fft: Array.new(32, 0.03),
          beat: true,
          beat_count: 99,
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
            trigger: proc { true },
            effect: { name: :crossfade, options: { duration: 1.0 } }
          }
        ],
        input_manager: input_manager,
        analysis_pipeline: pipeline
      )
      allow(broadcaster).to receive(:file_transport_source?).and_return(true)
      broadcaster.sync_transport(playing: false, position_seconds: 0.0)

      broadcaster.tick(0.1, Array.new(1024, 0.0))
      expect(broadcaster.current_scene_snapshot[:name]).to eq("intro")

      broadcaster.sync_transport(playing: true, position_seconds: 0.0)
      broadcaster.tick(0.2, Array.new(1024, 0.0))
      expect(broadcaster.current_scene_snapshot[:name]).to eq("drop")
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
