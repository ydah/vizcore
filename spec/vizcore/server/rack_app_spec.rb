# frozen_string_literal: true

require "rack/mock"
require "tmpdir"
require "vizcore/server/rack_app"

RSpec.describe Vizcore::Server::RackApp do
  subject(:app) { described_class.new(frontend_root: Vizcore.frontend_root) }

  it "serves the frontend entrypoint" do
    response = Rack::MockRequest.new(app).get("/")

    expect(response.status).to eq(200)
    expect(response.headers["content-type"]).to include("text/html")
    expect(response.body).to include("Vizcore Live")
    expect(response.body).to include('data-projector-mode="false"')
    expect(response.body).to include('data-display-mode="auto"')
  end

  it "returns health status as json" do
    response = Rack::MockRequest.new(app).get("/health")

    expect(response.status).to eq(200)
    expect(response.headers["content-type"]).to include("application/json")
    expect(response.body).to include("\"status\":\"ok\"")
  end

  it "rejects path traversal" do
    response = Rack::MockRequest.new(app).get("/../README.md")
    expect(response.status).to eq(404)
  end

  it "returns runtime metadata" do
    response = Rack::MockRequest.new(app).get("/runtime")

    expect(response.status).to eq(200)
    expect(response.headers["content-type"]).to include("application/json")
    expect(response.body).to include("\"audio_source\":\"unknown\"")
    expect(response.body).to include("\"scene_names\":[]")
    expect(response.body).to include("\"key_mappings\":[]")
    expect(response.body).to include("\"control_preset\":{}")
    expect(response.body).to include("\"projector_mode\":false")
  end

  it "serves projector output without operator UI by default" do
    response = Rack::MockRequest.new(app).get("/projector")

    expect(response.status).to eq(200)
    expect(response.body).to include('data-projector-mode="true"')
    expect(response.body).to include('data-display-mode="projector"')
  end

  it "serves a control panel with operator UI enabled" do
    response = Rack::MockRequest.new(app).get("/control")

    expect(response.status).to eq(200)
    expect(response.body).to include('data-projector-mode="false"')
    expect(response.body).to include('data-display-mode="control"')
  end

  it "serves the root entrypoint in projector mode when configured" do
    projector_app = described_class.new(frontend_root: Vizcore.frontend_root, projector_mode: true)

    root = Rack::MockRequest.new(projector_app).get("/")
    control = Rack::MockRequest.new(projector_app).get("/control")
    runtime = Rack::MockRequest.new(projector_app).get("/runtime")

    expect(root.body).to include('data-projector-mode="true"')
    expect(root.body).to include('data-display-mode="projector"')
    expect(control.body).to include('data-projector-mode="false"')
    expect(control.body).to include('data-display-mode="control"')
    expect(runtime.body).to include("\"projector_mode\":true")
  end

  it "returns 404 for audio endpoint when file source is disabled" do
    response = Rack::MockRequest.new(app).get("/audio-file")
    expect(response.status).to eq(404)
  end

  it "exposes runtime metadata and bytes for configured file source" do
    fixture = Vizcore.root.join("spec", "fixtures", "audio", "pulse16_mono.wav")
    file_app = described_class.new(
      frontend_root: Vizcore.frontend_root,
      audio_source: :file,
      audio_file: fixture
    )

    runtime = Rack::MockRequest.new(file_app).get("/runtime")
    expect(runtime.status).to eq(200)
    expect(runtime.body).to include("\"audio_source\":\"file\"")
    expect(runtime.body).to include("\"audio_file_url\":\"/audio-file\"")
    expect(runtime.body).to include("\"scene_names\":[]")

    audio = Rack::MockRequest.new(file_app).get("/audio-file")
    expect(audio.status).to eq(200)
    expect(audio.headers["content-type"]).to include("audio")
    expect(audio.headers["accept-ranges"]).to eq("bytes")
    expect(audio.body.bytesize).to be > 0
  end

  it "includes scene names in runtime metadata" do
    runtime_app = described_class.new(
      frontend_root: Vizcore.frontend_root,
      scene_names: %i[build drop],
      tap_tempo_key: :t,
      key_mappings: [
        { key: "d", action: { type: :switch_scene, scene: :drop } },
        { key: " ", action: { type: :live_control, control: :freeze } }
      ],
      globals: { global_intensity: 0.75 }
    )

    response = Rack::MockRequest.new(runtime_app).get("/runtime")

    expect(response.status).to eq(200)
    expect(response.body).to include("\"scene_names\":[\"build\",\"drop\"]")
    expect(response.body).to include("\"tap_tempo_key\":\"t\"")
    expect(response.body).to include("\"key_mappings\":[{\"key\":\"d\",\"action\":{\"type\":\"switch_scene\",\"scene\":\"drop\"}}")
    expect(response.body).to include("{\"key\":\"space\",\"action\":{\"type\":\"live_control\",\"control\":\"freeze\"}}")
    expect(response.body).to include("\"globals\":{\"global_intensity\":0.75}")
  end

  it "includes control presets in runtime metadata" do
    runtime_app = described_class.new(
      frontend_root: Vizcore.frontend_root,
      control_preset: {
        visual_settings: { visualGain: 3.25 },
        midi_learn_bindings: { "cc:1:7" => { type: "live_control", control: "freeze" } }
      }
    )

    response = Rack::MockRequest.new(runtime_app).get("/runtime")

    expect(response.status).to eq(200)
    expect(response.body).to include("\"visual_settings\":{\"visualGain\":3.25}")
    expect(response.body).to include("\"midi_learn_bindings\":{\"cc:1:7\":{\"type\":\"live_control\",\"control\":\"freeze\"}}")
  end

  it "injects and serves configured plugin assets" do
    Dir.mktmpdir("vizcore-plugin-assets") do |dir|
      asset_path = Pathname.new(dir).join("laser-renderer.js")
      asset_path.write("globalThis.__laserPluginLoaded = true;")
      runtime_app = described_class.new(
        frontend_root: Vizcore.frontend_root,
        plugin_assets: [asset_path]
      )

      root = Rack::MockRequest.new(runtime_app).get("/")
      runtime = Rack::MockRequest.new(runtime_app).get("/runtime")
      asset = Rack::MockRequest.new(runtime_app).get("/plugins/0/laser-renderer.js")

      expect(root.body).to include('<script type="module" src="/plugins/0/laser-renderer.js"></script>')
      expect(runtime.body).to include("\"plugin_assets\":[\"/plugins/0/laser-renderer.js\"]")
      expect(asset.status).to eq(200)
      expect(asset.body).to include("__laserPluginLoaded")
    end
  end

  it "supports byte range requests for audio file streaming" do
    fixture = Vizcore.root.join("spec", "fixtures", "audio", "kick_120bpm.wav")
    file_app = described_class.new(
      frontend_root: Vizcore.frontend_root,
      audio_source: :file,
      audio_file: fixture
    )

    response = Rack::MockRequest.new(file_app).get("/audio-file", "HTTP_RANGE" => "bytes=0-99")

    expect(response.status).to eq(206)
    expect(response.headers["content-range"]).to start_with("bytes 0-99/")
    expect(response.body.bytesize).to eq(100)
  end

  it "returns 416 for invalid byte ranges" do
    fixture = Vizcore.root.join("spec", "fixtures", "audio", "kick_120bpm.wav")
    file_app = described_class.new(
      frontend_root: Vizcore.frontend_root,
      audio_source: :file,
      audio_file: fixture
    )

    response = Rack::MockRequest.new(file_app).get("/audio-file", "HTTP_RANGE" => "bytes=9999999-")

    expect(response.status).to eq(416)
    expect(response.headers["content-range"]).to match(%r{\Abytes \*/\d+\z})
  end
end
