# frozen_string_literal: true

require "json"
require "vizcore/server/websocket_handler"

RSpec.describe Vizcore::Server::WebSocketHandler do
  FakeSocket = Struct.new(:messages, :buffered_amount) do
    def send(message)
      messages << message
    end
  end

  before do
    described_class.send(:sockets).clear
    described_class.instance_variable_set(:@dropped_frame_count, 0)
    allow(described_class).to receive(:faye_websocket_class).and_return(Class.new)
    allow(described_class).to receive(:event_machine_reactor_running?).and_return(false)
  end

  after do
    described_class.send(:sockets).clear
    described_class.instance_variable_set(:@dropped_frame_count, 0)
    described_class.clear_message_handler
  end

  it "adds the protocol version to broadcast envelopes" do
    socket = FakeSocket.new([])
    described_class.send(:register, socket)

    described_class.broadcast(type: "audio_frame", payload: { bpm: 120 })

    message = JSON.parse(socket.messages.first)
    expect(message).to eq(
      "protocol" => "vizcore.frame.v1",
      "type" => "audio_frame",
      "payload" => { "bpm" => 120 }
    )
  end

  it "drops audio frames for sockets with large pending buffers" do
    socket = FakeSocket.new([], described_class::MAX_BUFFERED_FRAME_BYTES + 1)
    described_class.send(:register, socket)

    described_class.broadcast(type: "audio_frame", payload: { bpm: 120 })

    expect(socket.messages).to be_empty
    expect(described_class.dropped_frame_count).to eq(1)
  end

  it "keeps scene changes even when a socket is backpressured" do
    socket = FakeSocket.new([], described_class::MAX_BUFFERED_FRAME_BYTES + 1)
    described_class.send(:register, socket)

    described_class.broadcast(type: "scene_change", payload: { from: "intro", to: "drop" })

    message = JSON.parse(socket.messages.first)
    expect(message).to include(
      "type" => "scene_change",
      "payload" => { "from" => "intro", "to" => "drop" }
    )
    expect(described_class.dropped_frame_count).to eq(0)
  end

  it "sends envelopes to a single socket" do
    socket = FakeSocket.new([])

    described_class.send_to(socket, type: "latency_probe", payload: { server_sent_at_ms: 1.0 })

    message = JSON.parse(socket.messages.first)
    expect(message).to eq(
      "protocol" => "vizcore.frame.v1",
      "type" => "latency_probe",
      "payload" => { "server_sent_at_ms" => 1.0 }
    )
  end

  it "passes the source socket to inbound message handlers" do
    socket = FakeSocket.new([])
    handled = nil
    described_class.on_message { |message, source_socket| handled = [message, source_socket] }

    described_class.send(:handle_message, socket, JSON.generate(type: "latency_probe", payload: {}))

    expect(handled).to eq([{ "type" => "latency_probe", "payload" => {} }, socket])
  end
end
