# frozen_string_literal: true

require "stringio"
require "vizcore/server/gallery_runner"

RSpec.describe Vizcore::Server::GalleryRunner do
  it "starts a puma server for the gallery app and stops it on exit" do
    app = instance_double(Vizcore::Server::GalleryApp)
    server = instance_double(Puma::Server, add_tcp_listener: nil, run: nil, stop: nil)
    output = StringIO.new

    allow(Vizcore::Server::GalleryApp).to receive(:new).and_return(app)
    allow(Puma::Server).to receive(:new).and_return(server)

    runner = described_class.new(host: "127.0.0.1", port: 4570, output: output)
    allow(runner).to receive(:wait_for_interrupt)

    runner.run

    expect(Puma::Server).to have_received(:new).with(app, nil, min_threads: 0, max_threads: 4)
    expect(server).to have_received(:add_tcp_listener).with("127.0.0.1", 4570)
    expect(server).to have_received(:run)
    expect(server).to have_received(:stop).with(true)
    expect(output.string).to include("Vizcore gallery: http://127.0.0.1:4570")
  end
end
