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
    let(:broadcaster) { instance_double(Vizcore::Server::FrameBroadcaster, start: nil, stop: nil) }

    it "configures puma thread options and shuts down cleanly" do
      allow(Vizcore::Server::RackApp).to receive(:new).and_return(rack_app)
      allow(Puma::Server).to receive(:new).and_return(puma_server)
      allow(Vizcore::Server::FrameBroadcaster).to receive(:new).and_return(broadcaster)

      runner = described_class.new(config, output: output)
      allow(runner).to receive(:wait_for_interrupt)

      runner.run

      expect(Puma::Server).to have_received(:new).with(rack_app, nil, min_threads: 0, max_threads: 4)
      expect(puma_server).to have_received(:add_tcp_listener).with("127.0.0.1", 4567)
      expect(puma_server).to have_received(:run)
      expect(puma_server).to have_received(:stop).with(true)
      expect(broadcaster).to have_received(:start)
      expect(broadcaster).to have_received(:stop)
    end
  end
end
