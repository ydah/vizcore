# frozen_string_literal: true

require "json"
require "timeout"
require "websocket-client-simple"

RSpec.describe "Phase 3 transitions", :e2e do
  class FakeInputManager
    attr_reader :frame_size, :sample_rate

    def initialize(frame_size: 1024, sample_rate: 44_100)
      @frame_size = frame_size
      @sample_rate = sample_rate
    end

    def start
      self
    end

    def stop
      self
    end

    def capture_frame
      Array.new(frame_size, 0.0)
    end
  end

  class SequencedAnalysisPipeline
    def initialize
      @frame_index = 0
    end

    def call(_samples)
      @frame_index += 1
      {
        amplitude: 0.55,
        bands: { sub: 0.1, low: 0.8, mid: 0.4, high: 0.2 },
        fft: Array.new(32, 0.05),
        beat: (@frame_index % 16).zero?,
        beat_count: @frame_index,
        bpm: 128.0
      }
    end
  end

  let(:intro_layers) { [{ name: :intro_layer, type: :geometry, params: {} }] }
  let(:drop_layers) { [{ name: :drop_layer, type: :shader, params: {} }] }
  let(:server) do
    E2EServerHelper::EmbeddedServer.new(
      scene_name: "intro",
      broadcaster_options: {
        scene_layers: intro_layers,
        scene_catalog: [
          { name: :intro, layers: intro_layers },
          { name: :drop, layers: drop_layers }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc { beat_count >= 50 },
            effect: { name: :crossfade, options: { duration: 1.5 } }
          }
        ],
        input_manager: FakeInputManager.new,
        analysis_pipeline: SequencedAnalysisPipeline.new
      }
    )
  end

  around do |example|
    server.start
    example.run
  ensure
    server.stop
  end

  it "emits scene_change and then streams frames for the new scene" do
    queue = Queue.new
    socket = WebSocket::Client::Simple.connect(server.websocket_url("/ws"))
    socket.on(:message) { |message| queue << JSON.parse(message.data) }

    seen_scene_change = nil
    seen_drop_frame = nil

    Timeout.timeout(6) do
      loop do
        message = queue.pop

        if message["type"] == "scene_change" && message.dig("payload", "to") == "drop"
          seen_scene_change = message
        elsif message["type"] == "audio_frame" && message.dig("payload", "scene", "name") == "drop"
          seen_drop_frame = message
        end

        break if seen_scene_change && seen_drop_frame
      end
    end

    expect(seen_scene_change.dig("payload", "from")).to eq("intro")
    expect(seen_scene_change.dig("payload", "to")).to eq("drop")
    expect(seen_scene_change.dig("payload", "effect", "name")).to eq("crossfade")
    expect(seen_drop_frame.dig("payload", "scene", "layers", 0, "name")).to eq("drop_layer")
  ensure
    socket&.close
  end
end
