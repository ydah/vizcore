# frozen_string_literal: true

require "stringio"
require "vizcore/config"
require "vizcore/server/runner"

RSpec.describe Vizcore::Server::Runner do
  describe "#run" do
    let(:scene_file) { Vizcore.root.join("examples", "basic.rb") }
    let(:config) { Vizcore::Config.new(scene_file: scene_file.to_s, host: "127.0.0.1", port: 4567) }
    let(:output) { StringIO.new }
    let(:rack_app) { instance_double(Vizcore::Server::RackApp) }
    let(:puma_server) { instance_double(Puma::Server, add_tcp_listener: nil, run: nil, stop: nil) }
    let(:broadcaster) { instance_double(Vizcore::Server::FrameBroadcaster, start: nil, stop: nil, update_scene: nil) }
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

      expect(Puma::Server).to have_received(:new).with(rack_app, nil, min_threads: 0, max_threads: 4)
      expect(Vizcore::Audio::InputManager).to have_received(:new).with(source: :mic, file_path: nil)
      expect(Vizcore::Server::FrameBroadcaster).to have_received(:new).with(
        scene_name: "basic",
        scene_layers: [hash_including(name: :wireframe_cube, type: :wireframe_cube)],
        input_manager: input_manager
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

      expect { runner.run }.to raise_error(ArgumentError, /Audio file not found/)
    end
  end
end
