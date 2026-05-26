# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "vizcore/config"
require "vizcore/server/runner"

RSpec.describe Vizcore::Server::Runner do
  describe "#run" do
    let(:scene_file) { Vizcore.root.join("examples", "basic.rb") }
    let(:config) { Vizcore::Config.new(scene_file: scene_file.to_s, host: "127.0.0.1", port: 4567) }
    let(:output) { StringIO.new }
    let(:rack_app) { instance_double(Vizcore::Server::RackApp) }
    let(:puma_server) { instance_double(Puma::Server, add_tcp_listener: nil, run: nil, stop: nil) }
    let(:broadcaster) do
      instance_double(
        Vizcore::Server::FrameBroadcaster,
        start: nil,
        sync_transport: nil,
        stop: nil,
        update_scene: nil,
        update_transition_definition: nil,
        update_analysis_settings: nil,
        current_scene_snapshot: { name: "intro", layers: [] }
      )
    end
    let(:input_manager) { instance_double(Vizcore::Audio::InputManager) }
    let(:watcher) { instance_double(Vizcore::Server::SceneDependencyWatcher, start: nil, stop: nil) }

    before do
      allow(Vizcore::Server::SceneDependencyWatcher).to receive(:new).and_return(watcher)
    end

    it "configures puma thread options and shuts down cleanly" do
      allow(Vizcore::Server::RackApp).to receive(:new).and_return(rack_app)
      allow(Puma::Server).to receive(:new).and_return(puma_server)
      allow(Vizcore::Audio::InputManager).to receive(:new).and_return(input_manager)
      allow(input_manager).to receive(:status).and_return(
        source: :mic,
        sample_rate: 44_100,
        frame_size: 1024,
        requested_sample_rate: 44_100,
        sample_rate_mismatch: false,
        ring_buffer: {}
      )
      allow(Vizcore::Server::FrameBroadcaster).to receive(:new).and_return(broadcaster)

      runner = described_class.new(config, output: output)
      allow(runner).to receive(:wait_for_interrupt)

      runner.run

      expect(Vizcore::Server::RackApp).to have_received(:new).with(
        frontend_root: Vizcore.frontend_root,
        audio_source: :mic,
        audio_file: nil,
        scene_names: ["basic"],
        tap_tempo_key: nil,
        key_mappings: [],
        globals: {},
        control_preset: nil,
        control_preset_path: nil,
        plugin_assets: [],
        projector_mode: false,
        runtime_status_provider: an_instance_of(Proc)
      )
      expect(Puma::Server).to have_received(:new).with(rack_app, nil, min_threads: 0, max_threads: 4)
      expect(Vizcore::Audio::InputManager).to have_received(:new).with(source: :mic, file_path: nil, audio_device: nil)
      expect(Vizcore::Server::FrameBroadcaster).to have_received(:new).with(
        hash_including(
          scene_name: "basic",
          scene_layers: [hash_including(name: :wireframe_cube, type: :wireframe_cube)],
          scene_catalog: [hash_including(name: :basic)],
          transitions: [],
          input_manager: input_manager,
          noise_gate: 0.01,
          error_reporter: an_instance_of(Proc)
        )
      )
      expect(Vizcore::Server::SceneDependencyWatcher).to have_received(:new).with(
        scene_file: scene_file.to_s,
        definition: hash_including(scenes: [hash_including(name: :basic)])
      )
      expect(watcher).to have_received(:start)
      expect(watcher).to have_received(:stop)
      expect(puma_server).to have_received(:add_tcp_listener).with("127.0.0.1", 4567)
      expect(puma_server).to have_received(:run)
      expect(puma_server).to have_received(:stop).with(true)
      expect(broadcaster).to have_received(:start)
      expect(broadcaster).to have_received(:stop)
    end

    it "starts from the timeline first entry scene when configured" do
      Dir.mktmpdir("vizcore-runner-timeline") do |dir|
        scene_path = File.join(dir, "timeline_scene.rb")
        File.write(
          scene_path,
          <<~RUBY
            Vizcore.define do
              scene :intro do
                layer :intro_layer do
                  type :geometry
                end
              end

              scene :drop do
                layer :drop_layer do
                  type :geometry
                end
              end

              timeline do
                at seconds(4.0), scene: :drop
              end
            end
          RUBY
        )

        timeline_config = Vizcore::Config.new(
          scene_file: scene_path,
          host: "127.0.0.1",
          port: 4567
        )
        timeline_broadcaster = instance_double(
          Vizcore::Server::FrameBroadcaster,
          start: nil,
          sync_transport: nil,
          stop: nil,
          update_scene: nil,
          update_transition_definition: nil,
          update_analysis_settings: nil,
          current_scene_snapshot: { name: "drop", layers: [] }
        )
        allow(Vizcore::Server::RackApp).to receive(:new).and_return(rack_app)
        allow(Puma::Server).to receive(:new).and_return(puma_server)
        allow(Vizcore::Audio::InputManager).to receive(:new).and_return(input_manager)
        allow(Vizcore::Server::FrameBroadcaster).to receive(:new).and_return(timeline_broadcaster)

        runner = described_class.new(timeline_config, output: output)
        allow(runner).to receive(:wait_for_interrupt)

        runner.run

        expect(Vizcore::Server::FrameBroadcaster).to have_received(:new).with(
          hash_including(
            scene_name: "drop",
            scene_layers: [hash_including(name: :drop_layer, type: :geometry)],
            initial_timeline_entry: hash_including(unit: :seconds, scene: :drop, at: 4.0)
          )
        )
      end
    end

    it "warns when requested sample rate differs from input stream sample rate" do
      allow(Vizcore::Server::RackApp).to receive(:new).and_return(rack_app)
      allow(Puma::Server).to receive(:new).and_return(puma_server)
      allow(Vizcore::Audio::InputManager).to receive(:new).and_return(input_manager)
      allow(input_manager).to receive(:status).and_return(
        source: :mic,
        sample_rate: 48_000,
        frame_size: 1024,
        requested_sample_rate: 44_100,
        sample_rate_mismatch: true,
        ring_buffer: {}
      )
      allow(Vizcore::Server::FrameBroadcaster).to receive(:new).and_return(broadcaster)

      runner = described_class.new(config, output: output)
      allow(runner).to receive(:wait_for_interrupt)

      runner.run

      expect(output.string).to include("Warning: requested audio sample rate 44100 does not match device sample rate 48000; analysis will use 48000.")
    end

    it "skips scene watcher when hot reload is disabled" do
      no_reload_config = Vizcore::Config.new(scene_file: scene_file.to_s, host: "127.0.0.1", port: 4567, reload: false)
      allow(Vizcore::Server::RackApp).to receive(:new).and_return(rack_app)
      allow(Puma::Server).to receive(:new).and_return(puma_server)
      allow(Vizcore::Audio::InputManager).to receive(:new).and_return(input_manager)
      allow(Vizcore::Server::FrameBroadcaster).to receive(:new).and_return(broadcaster)

      runner = described_class.new(no_reload_config, output: output)
      allow(runner).to receive(:wait_for_interrupt)

      runner.run

      expect(Vizcore::Server::SceneDependencyWatcher).not_to have_received(:new)
      expect(output.string).to include("Hot reload: disabled")
    end

    it "rejects public host binding unless explicitly allowed" do
      public_config = Vizcore::Config.new(scene_file: scene_file.to_s, host: "0.0.0.0", port: 4567)

      expect do
        described_class.new(public_config, output: output).run
      end.to raise_error(Vizcore::ConfigurationError, /allow-public-control/)
    end

    it "allows public host binding when explicitly opted in" do
      public_config = Vizcore::Config.new(
        scene_file: scene_file.to_s,
        host: "0.0.0.0",
        port: 4567,
        allow_public_control: true
      )
      allow(Vizcore::Server::RackApp).to receive(:new).and_return(rack_app)
      allow(Puma::Server).to receive(:new).and_return(puma_server)
      allow(Vizcore::Audio::InputManager).to receive(:new).and_return(input_manager)
      allow(Vizcore::Server::FrameBroadcaster).to receive(:new).and_return(broadcaster)

      runner = described_class.new(public_config, output: output)
      allow(runner).to receive(:wait_for_interrupt)

      runner.run

      expect(puma_server).to have_received(:add_tcp_listener).with("0.0.0.0", 4567)
    end

    it "passes file source metadata to RackApp when file input is enabled" do
      fixture = Vizcore.root.join("spec", "fixtures", "audio", "pulse16_mono.wav")
      file_config = Vizcore::Config.new(
        scene_file: scene_file.to_s,
        host: "127.0.0.1",
        port: 4567,
        audio_source: :file,
        audio_file: fixture.to_s
      )
      allow(Vizcore::Server::RackApp).to receive(:new).and_return(rack_app)
      allow(Puma::Server).to receive(:new).and_return(puma_server)
      allow(Vizcore::Audio::InputManager).to receive(:new).and_return(input_manager)
      allow(Vizcore::Server::FrameBroadcaster).to receive(:new).and_return(broadcaster)

      runner = described_class.new(file_config, output: output)
      allow(runner).to receive(:wait_for_interrupt)

      runner.run

      expect(Vizcore::Server::RackApp).to have_received(:new).with(
        frontend_root: Vizcore.frontend_root,
        audio_source: :file,
        audio_file: file_config.audio_file,
        scene_names: ["basic"],
        tap_tempo_key: nil,
        key_mappings: [],
        globals: {},
        control_preset: nil,
        control_preset_path: nil,
        plugin_assets: [],
        projector_mode: false,
        runtime_status_provider: an_instance_of(Proc)
      )
      expect(broadcaster).to have_received(:sync_transport).with(playing: false, position_seconds: 0.0)
    end

    it "uses recorded features instead of live audio when a feature file is configured" do
      Dir.mktmpdir("vizcore-runner-features") do |dir|
        feature_path = File.join(dir, "features.json")
        File.write(feature_path, "{}")
        feature_config = Vizcore::Config.new(
          scene_file: scene_file.to_s,
          host: "127.0.0.1",
          port: 4567,
          audio_source: :file,
          feature_file: feature_path
        )
        replay = instance_double(Vizcore::Analysis::FeatureReplay)
        allow(Vizcore::Analysis::FeatureReplay).to receive(:new).and_return(replay)
        allow(Vizcore::Server::RackApp).to receive(:new).and_return(rack_app)
        allow(Puma::Server).to receive(:new).and_return(puma_server)
        allow(Vizcore::Audio::InputManager).to receive(:new).and_return(input_manager)
        allow(Vizcore::Server::FrameBroadcaster).to receive(:new).and_return(broadcaster)

        runner = described_class.new(feature_config, output: output)
        allow(runner).to receive(:wait_for_interrupt)

        runner.run

        expect(Vizcore::Server::RackApp).to have_received(:new).with(
          hash_including(audio_source: :features, audio_file: nil)
        )
        expect(Vizcore::Audio::InputManager).to have_received(:new).with(source: :dummy, file_path: nil, audio_device: nil)
        expect(Vizcore::Analysis::FeatureReplay).to have_received(:new).with(path: feature_config.feature_file)
        expect(Vizcore::Server::FrameBroadcaster).to have_received(:new).with(
          hash_including(analysis_pipeline: replay)
        )
        expect(broadcaster).not_to have_received(:sync_transport)
        expect(output.string).to include("Feature replay: #{feature_config.feature_file}")
      end
    end

    it "passes projector mode to RackApp" do
      projector_config = Vizcore::Config.new(
        scene_file: scene_file.to_s,
        host: "127.0.0.1",
        port: 4567,
        projector_mode: true
      )
      allow(Vizcore::Server::RackApp).to receive(:new).and_return(rack_app)
      allow(Puma::Server).to receive(:new).and_return(puma_server)
      allow(Vizcore::Audio::InputManager).to receive(:new).and_return(input_manager)
      allow(Vizcore::Server::FrameBroadcaster).to receive(:new).and_return(broadcaster)

      runner = described_class.new(projector_config, output: output)
      allow(runner).to receive(:wait_for_interrupt)

      runner.run

      expect(Vizcore::Server::RackApp).to have_received(:new).with(
        hash_including(projector_mode: true)
      )
    end

    it "passes plugin assets to RackApp" do
      Dir.mktmpdir("vizcore-runner-plugin-assets") do |dir|
        asset_path = File.join(dir, "plugin.js")
        File.write(asset_path, "export {};")
        plugin_config = Vizcore::Config.new(
          scene_file: scene_file.to_s,
          host: "127.0.0.1",
          port: 4567,
          plugin_assets: [asset_path]
        )
        allow(Vizcore::Server::RackApp).to receive(:new).and_return(rack_app)
        allow(Puma::Server).to receive(:new).and_return(puma_server)
        allow(Vizcore::Audio::InputManager).to receive(:new).and_return(input_manager)
        allow(Vizcore::Server::FrameBroadcaster).to receive(:new).and_return(broadcaster)

        runner = described_class.new(plugin_config, output: output)
        allow(runner).to receive(:wait_for_interrupt)

        runner.run

        expect(Vizcore::Server::RackApp).to have_received(:new).with(
          hash_including(plugin_assets: [Pathname.new(asset_path).expand_path])
        )
      end
    end

    it "hot-reloads scene changes and broadcasts config updates" do
      callback = nil
      allow(Vizcore::Server::RackApp).to receive(:new).and_return(rack_app)
      allow(Puma::Server).to receive(:new).and_return(puma_server)
      allow(Vizcore::Audio::InputManager).to receive(:new).and_return(input_manager)
      allow(Vizcore::Server::FrameBroadcaster).to receive(:new).and_return(broadcaster)
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)
      allow(Vizcore::Server::SceneDependencyWatcher).to receive(:new) do |scene_file:, definition:, &block|
        expect(scene_file).to eq(config.scene_file.to_s)
        expect(definition).to include(:scenes)
        callback = block
        watcher
      end
      allow(watcher).to receive(:start) do
        callback&.call(
          {
            scenes: [
              {
                name: :updated,
                layers: [{ name: :layer, type: :shader, params: {} }]
              }
            ],
            key_mappings: [
              { key: "u", action: { type: :switch_scene, scene: "updated" } }
            ]
          },
          scene_file
        )
      end

      runner = described_class.new(config, output: output)
      allow(runner).to receive(:wait_for_interrupt)

      runner.run

      expect(broadcaster).to have_received(:update_scene).with(
        scene_name: :updated,
        scene_layers: [hash_including(name: :layer, type: :shader)]
      )
      expect(broadcaster).to have_received(:update_transition_definition).with(
        scenes: [hash_including(name: :updated)],
        transitions: []
      )
      expect(broadcaster).to have_received(:update_analysis_settings).with(
        hash_including(audio_normalize: nil, bpm: nil, bpm_lock: false)
      )
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "config_update",
        payload: hash_including(
          scene: hash_including(name: :updated),
          scenes: ["updated"],
          key_mappings: [hash_including(key: "u")]
        )
      )
    end

    it "broadcasts scene reload failures while keeping the last good scene" do
      callback = nil
      allow(Vizcore::Server::RackApp).to receive(:new).and_return(rack_app)
      allow(Puma::Server).to receive(:new).and_return(puma_server)
      allow(Vizcore::Audio::InputManager).to receive(:new).and_return(input_manager)
      allow(Vizcore::Server::FrameBroadcaster).to receive(:new).and_return(broadcaster)
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)
      allow(Vizcore::Server::SceneDependencyWatcher).to receive(:new) do |scene_file:, definition:, &block|
        expect(scene_file).to eq(config.scene_file.to_s)
        expect(definition).to include(:scenes)
        callback = block
        watcher
      end
      allow(watcher).to receive(:start) do
        callback&.call(
          {
            scenes: [
              {
                name: :broken,
                layers: [{ name: :shader_art, type: :shader, glsl: "missing.frag", params: {} }]
              }
            ]
          },
          scene_file
        )
      end

      runner = described_class.new(config, output: output)
      allow(runner).to receive(:wait_for_interrupt)

      runner.run

      expect(broadcaster).not_to have_received(:update_scene).with(
        scene_name: :broken,
        scene_layers: anything
      )
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "runtime_error",
        payload: hash_including(
          source: "scene_reload",
          event: "scene_reload_failed",
          context: "Scene reload failed",
          keeping_last_good_scene: true
        )
      )
    end

    it "switches scene from client websocket message" do
      runner = described_class.new(config, output: output)
      broadcaster = instance_double(
        Vizcore::Server::FrameBroadcaster,
        current_scene_snapshot: { name: "build", layers: [] },
        update_scene: nil
      )
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)
      runner.send(
        :replace_scene_catalog,
        [
          { name: :build, layers: [{ name: :a }] },
          { name: :drop, layers: [{ name: :b }] }
        ]
      )

      runner.send(
        :handle_client_message,
        { "type" => "switch_scene", "payload" => { "scene" => "drop" } },
        broadcaster
      )

      expect(broadcaster).to have_received(:update_scene).with(
        scene_name: :drop,
        scene_layers: [hash_including(name: :b)]
      )
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "scene_change",
        payload: hash_including(
          from: "build",
          to: "drop",
          source: "ui"
        )
      )
    end

    it "applies configured manual scene switch effect when websocket message omits one" do
      configured_config = Vizcore::Config.new(
        scene_file: scene_file,
        host: "127.0.0.1",
        port: 4567,
        scene_switch_effect: "crossfade",
        scene_switch_effect_duration: 0.5
      )
      runner = described_class.new(configured_config, output: output)
      broadcaster = instance_double(
        Vizcore::Server::FrameBroadcaster,
        current_scene_snapshot: { name: "build", layers: [] },
        update_scene: nil
      )
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)
      runner.send(
        :replace_scene_catalog,
        [
          { name: :build, layers: [{ name: :a }] },
          { name: :drop, layers: [{ name: :b }] }
        ]
      )

      runner.send(
        :handle_client_message,
        { "type" => "switch_scene", "payload" => { "scene" => "drop" } },
        broadcaster
      )

      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "scene_change",
        payload: hash_including(
          from: "build",
          to: "drop",
          source: "ui",
          effect: { name: :crossfade, options: { duration: 0.5 } }
        )
      )
    end

    it "switches scene from client websocket message with transition effect" do
      runner = described_class.new(config, output: output)
      broadcaster = instance_double(
        Vizcore::Server::FrameBroadcaster,
        current_scene_snapshot: { name: "build", layers: [] },
        update_scene: nil
      )
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)
      runner.send(
        :replace_scene_catalog,
        [
          { name: :build, layers: [{ name: :a }] },
          { name: :drop, layers: [{ name: :b }] }
        ]
      )

      runner.send(
        :handle_client_message,
        {
          "type" => "switch_scene",
          "payload" => {
            "scene" => "drop",
            "effect" => { "name" => "crossfade", "options" => { "duration" => 0.45 } }
          }
        },
        broadcaster
      )

      expect(broadcaster).to have_received(:update_scene).with(
        scene_name: :drop,
        scene_layers: [hash_including(name: :b)]
      )
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "scene_change",
        payload: hash_including(
          from: "build",
          to: "drop",
          source: "ui",
          effect: { name: "crossfade", options: { "duration" => 0.45 } }
        )
      )
    end

    it "applies custom shape param messages from the browser" do
      runner = described_class.new(config, output: output)
      broadcaster = instance_double(Vizcore::Server::FrameBroadcaster)
      allow(broadcaster).to receive(:set_custom_shape_param).and_return(
        "generated" => { 0 => { "radius" => 88.0 } }
      )
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)

      runner.send(
        :handle_client_message,
        {
          "type" => "custom_shape_param",
          "payload" => {
            "layer" => "generated",
            "custom_shape_index" => 0,
            "param" => "radius",
            "value" => 88
          }
        },
        broadcaster
      )

      expect(broadcaster).to have_received(:set_custom_shape_param).with(
        layer_name: "generated",
        custom_shape_index: 0,
        param: "radius",
        value: 88
      )
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "config_update",
        payload: {
          custom_shape_params: { "generated" => { 0 => { "radius" => 88.0 } } },
          source: "ui"
        }
      )
    end

    it "applies MIDI next and previous scene actions" do
      runner = described_class.new(config, output: output)
      broadcaster = instance_double(
        Vizcore::Server::FrameBroadcaster,
        current_scene_snapshot: { name: "build", layers: [] },
        update_scene: nil
      )
      executor = instance_double(Vizcore::DSL::MidiMapExecutor, globals: {})
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)
      runner.send(
        :replace_scene_catalog,
        [
          { name: :intro, layers: [{ name: :a }] },
          { name: :build, layers: [{ name: :b }] },
          { name: :drop, layers: [{ name: :c }] }
        ]
      )

      runner.send(:apply_midi_action, { type: :next_scene, effect: { name: :crossfade } }, executor, broadcaster)

      expect(broadcaster).to have_received(:update_scene).with(
        scene_name: :drop,
        scene_layers: [hash_including(name: :c)]
      )
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "scene_change",
        payload: hash_including(from: "build", to: "drop", source: "midi", effect: { name: :crossfade })
      )
    end

    it "applies MIDI live control actions" do
      runner = described_class.new(config, output: output)
      executor = instance_double(Vizcore::DSL::MidiMapExecutor, globals: {})
      broadcaster = instance_double(Vizcore::Server::FrameBroadcaster)
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)

      runner.send(
        :apply_midi_action,
        { type: :live_control, control: "blackout", value: true, fade: 0.25, release: 0.8, color: [51, 102, 255, 128] },
        executor,
        broadcaster
      )

      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "config_update",
        payload: hash_including(
          live_controls: {
            "blackout" => { "enabled" => true, "fade" => 0.25, "release" => 0.8, "color" => [0.2, 0.4, 1, 0.5019607843137255] },
            "freeze" => { "enabled" => false }
          },
          source: "midi"
        )
      )
    end

    it "switches scene from OSC message" do
      runner = described_class.new(config, output: output)
      runner.instance_variable_set(:@osc_runtime_active, true)
      broadcaster = instance_double(
        Vizcore::Server::FrameBroadcaster,
        current_scene_snapshot: { name: "build", layers: [] },
        update_scene: nil
      )
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)
      runner.send(
        :replace_scene_catalog,
        [
          { name: :build, layers: [{ name: :a }] },
          { name: :drop, layers: [{ name: :b }] }
        ]
      )

      runner.send(
        :handle_osc_message,
        Vizcore::Sync::OscMessage.new(address: "/vizcore/scene", arguments: ["drop"]),
        broadcaster
      )

      expect(broadcaster).to have_received(:update_scene).with(
        scene_name: :drop,
        scene_layers: [hash_including(name: :b)]
      )
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "scene_change",
        payload: hash_including(source: "osc", to: "drop")
      )
    end

    it "handles OSC bundles as multiple messages" do
      runner = described_class.new(config, output: output)
      runner.instance_variable_set(:@osc_runtime_active, true)
      broadcaster = instance_double(
        Vizcore::Server::FrameBroadcaster,
        current_scene_snapshot: { name: "build", layers: [] },
        update_scene: nil
      )
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)
      runner.send(
        :replace_scene_catalog,
        [
          { name: :build, layers: [{ name: :a }] },
          { name: :drop, layers: [{ name: :b }] }
        ]
      )

      runner.send(
        :handle_osc_messages,
        [
          Vizcore::Sync::OscMessage.new(address: "/vizcore/scene", arguments: ["drop"]),
          Vizcore::Sync::OscMessage.new(address: "/vizcore/scene", arguments: ["build"])
        ],
        broadcaster
      )

      expect(broadcaster).to have_received(:update_scene).with(
        scene_name: :drop,
        scene_layers: [hash_including(name: :b)]
      )
      expect(broadcaster).to have_received(:update_scene).with(
        scene_name: :build,
        scene_layers: [hash_including(name: :a)]
      )
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "scene_change",
        payload: hash_including(source: "osc", to: "drop")
      )
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "scene_change",
        payload: hash_including(source: "osc", to: "build")
      )
    end

    it "schedules OSC messages with future timetags" do
      runner = described_class.new(config, output: output)
      runner.instance_variable_set(:@osc_runtime_active, true)
      broadcaster = instance_double(
        Vizcore::Server::FrameBroadcaster,
        current_scene_snapshot: { name: "build", layers: [] },
        update_scene: nil
      )
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)
      runner.send(
        :replace_scene_catalog,
        [
          { name: :build, layers: [{ name: :a }] },
          { name: :drop, layers: [{ name: :b }] }
        ]
      )

      baseline_time = 2_000_000_000.0
      allow(runner).to receive(:wall_clock_seconds).and_return(baseline_time)

      runner.send(
        :handle_osc_message,
        Vizcore::Sync::OscMessage.new(address: "/vizcore/scene", arguments: ["drop"], timetag: baseline_time + 0.05),
        broadcaster
      )

      expect(broadcaster).not_to have_received(:update_scene)
      sleep(0.08)
      expect(broadcaster).to have_received(:update_scene).with(
        scene_name: :drop,
        scene_layers: [hash_including(name: :b)]
      )
    end

    it "switches scene from OSC message with transition effect" do
      runner = described_class.new(config, output: output)
      runner.instance_variable_set(:@osc_runtime_active, true)
      broadcaster = instance_double(
        Vizcore::Server::FrameBroadcaster,
        current_scene_snapshot: { name: "build", layers: [] },
        update_scene: nil
      )
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)
      runner.send(
        :replace_scene_catalog,
        [
          { name: :build, layers: [{ name: :a }] },
          { name: :drop, layers: [{ name: :b }] }
        ]
      )

      runner.send(
        :handle_osc_message,
        Vizcore::Sync::OscMessage.new(address: "/vizcore/scene", arguments: ["drop", "crossfade", 0.45]),
        broadcaster
      )

      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "scene_change",
        payload: hash_including(
          source: "osc",
          from: "build",
          to: "drop",
          effect: { name: :crossfade, options: { duration: 0.45 } }
        )
      )
    end

    it "applies OSC tap tempo messages" do
      runner = described_class.new(config, output: output)
      runner.instance_variable_set(:@osc_runtime_active, true)
      broadcaster = instance_double(Vizcore::Server::FrameBroadcaster)
      runner.instance_variable_set(:@tap_tempo_key, "t")
      allow(runner).to receive(:wall_clock_ms).and_return(2_500.0)
      allow(broadcaster).to receive(:tap_tempo).and_return(121.0)
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)

      runner.send(
        :handle_osc_message,
        Vizcore::Sync::OscMessage.new(address: "/vizcore/tap"),
        broadcaster
      )

      expect(broadcaster).to have_received(:tap_tempo).with(timestamp_ms: 2_500.0)
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "config_update",
        payload: hash_including(bpm: 121.0, bpm_lock: true)
      )
    end

    it "applies OSC BPM lock messages" do
      runner = described_class.new(config, output: output)
      runner.instance_variable_set(:@osc_runtime_active, true)
      broadcaster = instance_double(Vizcore::Server::FrameBroadcaster, lock_bpm: 128.0)
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)

      runner.send(
        :handle_osc_message,
        Vizcore::Sync::OscMessage.new(address: "/vizcore/bpm", arguments: [128.0]),
        broadcaster
      )

      expect(broadcaster).to have_received(:lock_bpm).with(128.0)
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "config_update",
        payload: hash_including(bpm: 128.0, bpm_lock: true, source: "osc")
      )
    end

    it "applies OSC global and live control messages" do
      runner = described_class.new(config, output: output)
      runner.instance_variable_set(:@osc_runtime_active, true)
      broadcaster = instance_double(Vizcore::Server::FrameBroadcaster)
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)

      runner.send(
        :handle_osc_message,
        Vizcore::Sync::OscMessage.new(address: "/vizcore/global/intensity", arguments: [0.75]),
        broadcaster
      )
      runner.send(
        :handle_osc_message,
        Vizcore::Sync::OscMessage.new(address: "/vizcore/live/blackout", arguments: [1, 0, 0.8, "#3366ff80"]),
        broadcaster
      )

      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "config_update",
        payload: hash_including(globals: { "intensity" => 0.75 }, source: "osc")
      )
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "config_update",
        payload: hash_including(
          live_controls: {
            "blackout" => { "enabled" => true, "fade" => 0.0, "release" => 0.8, "color" => [0.2, 0.4, 1, 0.5019607843137255] },
            "freeze" => { "enabled" => false }
          },
          source: "osc"
        )
      )
    end

    it "applies OSC layer params and normalizes ranged values" do
      runner = described_class.new(config, output: output)
      runner.instance_variable_set(:@osc_runtime_active, true)
      broadcaster = instance_double(
        Vizcore::Server::FrameBroadcaster,
        set_layer_param: { "rings" => { "opacity" => 0.5 } }
      )
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)

      runner.send(
        :handle_osc_message,
        Vizcore::Sync::OscMessage.new(address: "/vizcore/layer/rings/opacity", arguments: [64, 0, 128]),
        broadcaster
      )

      expect(broadcaster).to have_received(:set_layer_param).with(
        layer_name: "rings",
        param: "opacity",
        value: 0.5
      )
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "config_update",
        payload: hash_including(layer_params: { "rings" => { "opacity" => 0.5 } }, source: "osc")
      )
    end

    it "normalizes OSC value with 0..127 preset" do
      runner = described_class.new(config, output: output)
      runner.instance_variable_set(:@osc_runtime_active, true)
      broadcaster = instance_double(
        Vizcore::Server::FrameBroadcaster,
        set_layer_param: { "rings" => { "opacity" => 0.5 } }
      )
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)

      runner.send(
        :handle_osc_message,
        Vizcore::Sync::OscMessage.new(address: "/vizcore/layer/rings/opacity", arguments: [64, "midi"]),
        broadcaster
      )

      expect(broadcaster).to have_received(:set_layer_param).with(
        layer_name: "rings",
        param: "opacity",
        value: (64.0 / 127.0)
      )
    end

    it "normalizes OSC value with range expression" do
      runner = described_class.new(config, output: output)
      runner.instance_variable_set(:@osc_runtime_active, true)
      broadcaster = instance_double(
        Vizcore::Server::FrameBroadcaster,
        set_layer_param: { "rings" => { "x" => 0.5 } }
      )
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)

      runner.send(
        :handle_osc_message,
        Vizcore::Sync::OscMessage.new(address: "/vizcore/layer/rings/x", arguments: [0, "-1..1"]),
        broadcaster
      )

      expect(broadcaster).to have_received(:set_layer_param).with(
        layer_name: "rings",
        param: "x",
        value: 0.5
      )
    end

    it "applies OSC transport messages for file input" do
      fixture = Vizcore.root.join("spec", "fixtures", "audio", "pulse16_mono.wav")
      file_config = Vizcore::Config.new(
        scene_file: scene_file.to_s,
        host: "127.0.0.1",
        port: 4567,
        audio_source: :file,
        audio_file: fixture.to_s
      )
      runner = described_class.new(file_config, output: output)
      runner.instance_variable_set(:@osc_runtime_active, true)
      broadcaster = instance_double(Vizcore::Server::FrameBroadcaster, sync_transport: nil)

      runner.send(
        :handle_osc_message,
        Vizcore::Sync::OscMessage.new(address: "/vizcore/transport/play", arguments: [12.5]),
        broadcaster
      )

      expect(broadcaster).to have_received(:sync_transport).with(playing: true, position_seconds: 12.5)
    end

    it "responds to client latency probes on the source socket" do
      runner = described_class.new(config, output: output)
      broadcaster = instance_double(Vizcore::Server::FrameBroadcaster)
      socket = instance_double("WebSocket")
      allow(runner).to receive(:wall_clock_ms).and_return(1_100.0, 1_101.5)
      allow(Vizcore::Server::WebSocketHandler).to receive(:send_to)

      runner.send(
        :handle_client_message,
        { "type" => "latency_probe", "payload" => { "client_sent_at_ms" => 1_000.0 } },
        broadcaster,
        socket
      )

      expect(Vizcore::Server::WebSocketHandler).to have_received(:send_to).with(
        socket,
        type: "latency_probe",
        payload: {
          client_sent_at_ms: 1_000.0,
          server_received_at_ms: 1_100.0,
          server_sent_at_ms: 1_101.5
        }
      )
    end

    it "forwards shader compile runtime errors from client" do
      runner = described_class.new(config, output: output)
      broadcaster = instance_double(Vizcore::Server::FrameBroadcaster)
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)

      runner.send(
        :handle_client_message,
        {
          "type" => "client_runtime_error",
          "payload" => {
            "source" => "shader",
            "event" => "shader_failed",
            "context" => "shader compile failed",
            "message" => "layer (shaders/custom.frag) [custom-shader] syntax error"
          }
        },
        broadcaster
      )

      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "runtime_error",
        payload: hash_including(
          source: "shader",
          event: "shader_failed",
          context: "shader compile failed",
          message: "layer (shaders/custom.frag) [custom-shader] syntax error"
        )
      )
    end

    it "applies tap tempo messages from the browser" do
      runner = described_class.new(config, output: output)
      broadcaster = instance_double(Vizcore::Server::FrameBroadcaster)
      runner.instance_variable_set(:@tap_tempo_key, "t")
      allow(broadcaster).to receive(:tap_tempo).and_return(120.0)
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)

      runner.send(
        :handle_client_message,
        { "type" => "tap_tempo", "payload" => { "client_tapped_at_ms" => 1_500.0 } },
        broadcaster
      )

      expect(broadcaster).to have_received(:tap_tempo).with(timestamp_ms: 1_500.0)
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "config_update",
        payload: hash_including(bpm: 120.0, bpm_lock: true, source: "tap_tempo")
      )
    end

    it "ignores tap tempo messages until tap tempo is configured" do
      runner = described_class.new(config, output: output)
      broadcaster = instance_double(Vizcore::Server::FrameBroadcaster)
      allow(broadcaster).to receive(:tap_tempo)
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)

      runner.send(
        :handle_client_message,
        { "type" => "tap_tempo", "payload" => { "client_tapped_at_ms" => 1_500.0 } },
        broadcaster
      )

      expect(broadcaster).not_to have_received(:tap_tempo)
      expect(Vizcore::Server::WebSocketHandler).not_to have_received(:broadcast)
    end

    it "raises when file source is selected without an existing file" do
      file_config = Vizcore::Config.new(
        scene_file: scene_file.to_s,
        host: "127.0.0.1",
        port: 4567,
        audio_source: :file,
        audio_file: "missing.wav"
      )
      runner = described_class.new(file_config, output: output)

      expect { runner.run }.to raise_error(Vizcore::ConfigurationError, /Audio file not found/)
    end

    it "raises when scene references missing glsl file" do
      Dir.mktmpdir("vizcore-runner-glsl") do |dir|
        missing_scene = File.join(dir, "missing_glsl_scene.rb")
        File.write(
          missing_scene,
          <<~RUBY
            Vizcore.define do
              scene :broken do
                layer :shader_art do
                  glsl "shaders/not_found.frag"
                end
              end
            end
          RUBY
        )
        broken_config = Vizcore::Config.new(scene_file: missing_scene, host: "127.0.0.1", port: 4567)
        runner = described_class.new(broken_config, output: output)

        expect { runner.run }.to raise_error(Vizcore::SceneLoadError, /GLSL file not found/)
      end
    end

    it "executes midi_map switch_scene action from midi note events" do
      midi_callback = nil
      midi_input = instance_double(Vizcore::Audio::MidiInput, stop: nil)
      definition = {
        scenes: [
          { name: :intro, layers: [{ name: :intro_layer, type: :geometry, params: {} }] },
          { name: :drop, layers: [{ name: :drop_layer, type: :shader, params: {} }] }
        ],
        transitions: [],
        midi: [],
        midi_maps: [
          { trigger: { note: 36 }, action: proc { switch_scene :drop } }
        ],
        globals: {}
      }
      event = Vizcore::Audio::MidiInput::Event.new(
        type: :note_on,
        channel: 0,
        data1: 36,
        data2: 100,
        raw: [0x90, 36, 100],
        timestamp: Time.now.to_f
      )

      allow(Vizcore::DSL::Engine).to receive(:load_file).and_return(definition)
      allow(Vizcore::Server::RackApp).to receive(:new).and_return(rack_app)
      allow(Puma::Server).to receive(:new).and_return(puma_server)
      allow(Vizcore::Audio::InputManager).to receive(:new).and_return(input_manager)
      allow(Vizcore::Server::FrameBroadcaster).to receive(:new).and_return(broadcaster)
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)
      allow(Vizcore::Audio::MidiInput).to receive(:new).and_return(midi_input)
      allow(midi_input).to receive(:start) do |&block|
        midi_callback = block
        midi_callback&.call(event)
        midi_input
      end

      runner = described_class.new(config, output: output)
      allow(runner).to receive(:wait_for_interrupt)

      runner.run

      expect(Vizcore::Audio::MidiInput).to have_received(:new).with(device: nil)
      expect(broadcaster).to have_received(:update_scene).with(
        scene_name: :drop,
        scene_layers: [hash_including(name: :drop_layer, type: :shader)]
      )
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "scene_change",
        payload: hash_including(
          from: "intro",
          to: "drop",
          source: "midi"
        )
      )
      expect(midi_input).to have_received(:stop)
    end
  end
end
