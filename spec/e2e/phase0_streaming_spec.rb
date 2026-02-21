# frozen_string_literal: true

require "json"
require "net/http"
require "timeout"
require "websocket-client-simple"

RSpec.describe "Phase 0 streaming", :e2e do
  let(:server) { E2EServerHelper::EmbeddedServer.new(scene_name: "basic") }

  around do |example|
    server.start
    example.run
  ensure
    server.stop
  end

  it "serves frontend assets over HTTP" do
    root_response = Net::HTTP.get_response(server.http_url("/"))
    script_response = Net::HTTP.get_response(server.http_url("/src/main.js"))

    expect(root_response).to be_a(Net::HTTPSuccess)
    expect(root_response.body).to include("Vizcore Phase 0")

    expect(script_response).to be_a(Net::HTTPSuccess)
    expect(script_response.body).to include("WebSocketClient")
  end

  it "pushes audio_frame messages over faye-websocket transport" do
    queue = Queue.new
    socket = WebSocket::Client::Simple.connect(server.websocket_url("/ws"))
    socket.on(:message) { |message| queue << message.data }

    raw_message = Timeout.timeout(5) { queue.pop }
    payload = JSON.parse(raw_message)

    expect(payload["type"]).to eq("audio_frame")
    expect(payload.dig("payload", "audio", "amplitude")).to be_a(Numeric)
    expect(payload.dig("payload", "scene", "name")).to eq("basic")
  ensure
    socket&.close
  end
end
