# frozen_string_literal: true

require "json"
require "vizcore/server/websocket_handler"

RSpec.describe Vizcore::Server::WebSocketHandler do
  FakeSocket = Struct.new(:messages, :buffered_amount) do
    def send(message)
      messages << message
    end

    def hash
      object_id.hash
    end

    def eql?(other)
      equal?(other)
    end
  end

  before do
    described_class.send(:sockets).clear
    described_class.instance_variable_set(:@dropped_frame_count, 0)
    described_class.send(:socket_backpressure_metrics).clear
    described_class.send(:socket_backpressure_totals)[:dropped_frames] = 0
    described_class.send(:socket_backpressure_totals)[:dropped_payload_bytes] = 0
    described_class.send(:socket_backpressure_totals)[:sent_frames] = 0
    described_class.send(:socket_backpressure_totals)[:sent_payload_bytes] = 0
    allow(described_class).to receive(:faye_websocket_class).and_return(Class.new)
    allow(described_class).to receive(:event_machine_reactor_running?).and_return(false)
  end

  after do
    described_class.send(:sockets).clear
    described_class.instance_variable_set(:@dropped_frame_count, 0)
    described_class.send(:socket_backpressure_metrics).clear
    described_class.send(:socket_backpressure_totals)[:dropped_frames] = 0
    described_class.send(:socket_backpressure_totals)[:dropped_payload_bytes] = 0
    described_class.send(:socket_backpressure_totals)[:sent_frames] = 0
    described_class.send(:socket_backpressure_totals)[:sent_payload_bytes] = 0
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

  it "tracks backpressure metrics for audio_frame drops and successful sends" do
    send_socket = FakeSocket.new([], 0)
    described_class.send(:register, send_socket)

    payload = { bpm: 120 }
    message = JSON.generate(protocol: described_class::PROTOCOL_VERSION, type: "audio_frame", payload: payload)
    described_class.send_to(send_socket, type: "audio_frame", payload: payload)

    status = described_class.backpressure_status
    expect(status[:threshold_bytes]).to eq(described_class::MAX_BUFFERED_FRAME_BYTES)
    expect(status[:active_clients]).to eq(1)
    expect(status[:total][:sent_frames]).to eq(1)
    expect(status[:total][:sent_payload_bytes]).to eq(message.bytesize)
    expect(status[:clients][0][:id]).to eq(send_socket.object_id.to_s)
    expect(status[:clients][0][:sent_frames]).to eq(1)
    expect(status[:clients][0][:sent_payload_bytes]).to eq(message.bytesize)
    expect(status[:clients][0][:dropped_frames]).to eq(0)

    drop_socket = FakeSocket.new([], described_class::MAX_BUFFERED_FRAME_BYTES + 1)
    described_class.send(:register, drop_socket)
    described_class.broadcast(type: "audio_frame", payload: payload)

    status = described_class.backpressure_status
    dropped_client = status[:clients].find { |entry| entry[:id] == drop_socket.object_id.to_s }
    expect(dropped_client[:dropped_frames]).to eq(1)
    expect(status[:total][:dropped_frames]).to eq(1)
    expect(status[:total][:dropped_payload_bytes]).to be >= message.bytesize
    expect(described_class.dropped_frame_count).to eq(1)
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

  it "assigns client role from websocket query string on registration" do
    socket = FakeSocket.new([])
    role = described_class.send(:websocket_role_for_env, "QUERY_STRING" => "role=control")
    described_class.send(:register, socket, role: role)

    described_class.broadcast(type: "audio_frame", payload: { bpm: 120 })
    described_class.broadcast(type: "audio_frame", payload: { bpm: 120 })
    described_class.broadcast(type: "audio_frame", payload: { bpm: 120 })
    described_class.broadcast(type: "audio_frame", payload: { bpm: 120 })

    expect(role).to eq(described_class::CONTROL_ROLE)
    parsed_messages = socket.messages.map { |message| JSON.parse(message) }
    expect(parsed_messages.length).to eq(2)
  end

  it "allows monitor sockets to send latency probes" do
    monitor_socket = FakeSocket.new([])
    handled_messages = []
    described_class.on_message { |message| handled_messages << message }
    described_class.send(:register, monitor_socket, role: described_class::MONITOR_ROLE)

    described_class.send(:handle_message, monitor_socket, JSON.generate(type: "latency_probe", payload: {}))

    expect(handled_messages).to eq([{ "type" => "latency_probe", "payload" => {} }])
  end

  it "blocks monitor sockets from scene control messages" do
    monitor_socket = FakeSocket.new([])
    handled_messages = []
    described_class.on_message { |message| handled_messages << message }
    described_class.send(:register, monitor_socket, role: described_class::MONITOR_ROLE)

    described_class.send(
      :handle_message,
      monitor_socket,
      JSON.generate(type: "switch_scene", payload: { scene: "build" })
    )

    expect(handled_messages).to be_empty
  end

  it "blocks projector sockets from scene control messages" do
    projector_socket = FakeSocket.new([])
    handled_messages = []
    described_class.on_message { |message| handled_messages << message }
    described_class.send(:register, projector_socket, role: described_class::PROJECTOR_ROLE)

    described_class.send(
      :handle_message,
      projector_socket,
      JSON.generate(type: "switch_scene", payload: { scene: "build" })
    )

    expect(handled_messages).to be_empty
  end

  it "allows projector sockets to report file transport playback" do
    projector_socket = FakeSocket.new([])
    handled_messages = []
    described_class.on_message { |message| handled_messages << message }
    described_class.send(:register, projector_socket, role: described_class::PROJECTOR_ROLE)

    described_class.send(
      :handle_message,
      projector_socket,
      JSON.generate(type: "transport_sync", payload: { playing: true, position_seconds: 1.25 })
    )

    expect(handled_messages).to eq([
      { "type" => "transport_sync", "payload" => { "playing" => true, "position_seconds" => 1.25 } }
    ])
  end

  it "keeps backpressure metrics client role field updated" do
    projector_socket = FakeSocket.new([])
    described_class.send(:register, projector_socket, role: described_class::PROJECTOR_ROLE)
    control_socket = FakeSocket.new([])
    described_class.send(:register, control_socket, role: described_class::CONTROL_ROLE)

    described_class.broadcast(type: "scene_change", payload: { from: "intro", to: "drop" })
    described_class.broadcast(type: "audio_frame", payload: { bpm: 120 })

    status = described_class.backpressure_status
    role_index = status[:clients].index { |entry| entry[:id] == control_socket.object_id.to_s }
    projector_entry = status[:clients].find { |entry| entry[:id] == projector_socket.object_id.to_s }

    expect(role_index).not_to be_nil
    expect(status[:clients][role_index][:role]).to eq(described_class::CONTROL_ROLE)
    expect(projector_entry[:role]).to eq(described_class::PROJECTOR_ROLE)
    expect(status[:clients][role_index][:sent_frames]).to be >= 1
  end

  it "accepts monitor role from query string" do
    role = described_class.send(:websocket_role_for_env, "QUERY_STRING" => "role=monitor")

    expect(role).to eq(described_class::MONITOR_ROLE)
  end

  it "normalizes unsupported query role values to projector" do
    role = described_class.send(:websocket_role_for_env, "QUERY_STRING" => "role=watcher")

    expect(role).to eq(described_class::PROJECTOR_ROLE)
  end
end
