# frozen_string_literal: true

require "json"
require "vizcore/server/websocket_handler"

RSpec.describe Vizcore::Server::WebSocketHandler do
  FakeSocket = Struct.new(:messages) do
    def send(message)
      messages << message
    end
  end

  before do
    described_class.send(:sockets).clear
    allow(described_class).to receive(:faye_websocket_class).and_return(Class.new)
    allow(described_class).to receive(:event_machine_reactor_running?).and_return(false)
  end

  after do
    described_class.send(:sockets).clear
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
end
