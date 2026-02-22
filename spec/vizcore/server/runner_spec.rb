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
        stop: nil,
        update_scene: nil,
        update_transition_definition: nil,
        current_scene_snapshot: { name: "intro", layers: [] }
      )
    end
    let(:input_manager) { instance_double(Vizcore::Audio::InputManager) }
    let(:watcher) { instance_double(Vizcore::DSL::FileWatcher, start: nil, stop: nil) }

    it "configures puma thread options and shuts down cleanly" do
      allow(Vizcore::Server::RackApp).to receive(:new).and_return(rack_app)
      allow(Puma::Server).to receive(:new).and_return(puma_server)
      allow(Vizcore::Audio::InputManager).to receive(:new).and_return(input_manager)
      allow(Vizcore::Server::FrameBroadcaster).to receive(:new).and_return(broadcaster)
      allow(Vizcore::DSL::Engine).to receive(:watch_file).and_return(watcher)

      runner = described_class.new(config, output: output)
      allow(runner).to receive(:wait_for_interrupt)

      runner.run

      expect(Vizcore::Server::RackApp).to have_received(:new).with(
        frontend_root: Vizcore.frontend_root,
        audio_source: :mic,
        audio_file: nil
      )
      expect(Puma::Server).to have_received(:new).with(rack_app, nil, min_threads: 0, max_threads: 4)
      expect(Vizcore::Audio::InputManager).to have_received(:new).with(source: :mic, file_path: nil)
      expect(Vizcore::Server::FrameBroadcaster).to have_received(:new).with(
        hash_including(
          scene_name: "basic",
          scene_layers: [hash_including(name: :wireframe_cube, type: :wireframe_cube)],
          scene_catalog: [hash_including(name: :basic)],
          transitions: [],
          input_manager: input_manager,
          error_reporter: an_instance_of(Proc)
        )
      )
      expect(Vizcore::DSL::Engine).to have_received(:watch_file).with(scene_file.to_s)
      expect(watcher).to have_received(:start)
      expect(watcher).to have_received(:stop)
      expect(puma_server).to have_received(:add_tcp_listener).with("127.0.0.1", 4567)
      expect(puma_server).to have_received(:run)
      expect(puma_server).to have_received(:stop).with(true)
      expect(broadcaster).to have_received(:start)
      expect(broadcaster).to have_received(:stop)
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
      allow(Vizcore::DSL::Engine).to receive(:watch_file).and_return(watcher)

      runner = described_class.new(file_config, output: output)
      allow(runner).to receive(:wait_for_interrupt)

      runner.run

      expect(Vizcore::Server::RackApp).to have_received(:new).with(
        frontend_root: Vizcore.frontend_root,
        audio_source: :file,
        audio_file: file_config.audio_file
      )
    end

    it "hot-reloads scene changes and broadcasts config updates" do
      callback = nil
      allow(Vizcore::Server::RackApp).to receive(:new).and_return(rack_app)
      allow(Puma::Server).to receive(:new).and_return(puma_server)
      allow(Vizcore::Audio::InputManager).to receive(:new).and_return(input_manager)
      allow(Vizcore::Server::FrameBroadcaster).to receive(:new).and_return(broadcaster)
      allow(Vizcore::Server::WebSocketHandler).to receive(:broadcast)
      allow(Vizcore::DSL::Engine).to receive(:watch_file) do |_, &block|
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
      expect(Vizcore::Server::WebSocketHandler).to have_received(:broadcast).with(
        type: "config_update",
        payload: {
          scene: hash_including(name: :updated)
        }
      )
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
      allow(Vizcore::DSL::Engine).to receive(:watch_file).and_return(watcher)
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
