# frozen_string_literal: true

require "rack/mock"
require "vizcore/server/rack_app"

RSpec.describe Vizcore::Server::RackApp do
  subject(:app) { described_class.new(frontend_root: Vizcore.frontend_root) }

  it "serves the frontend entrypoint" do
    response = Rack::MockRequest.new(app).get("/")

    expect(response.status).to eq(200)
    expect(response.headers["content-type"]).to include("text/html")
    expect(response.body).to include("Vizcore Live")
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
      scene_names: %i[build drop]
    )

    response = Rack::MockRequest.new(runtime_app).get("/runtime")

    expect(response.status).to eq(200)
    expect(response.body).to include("\"scene_names\":[\"build\",\"drop\"]")
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
