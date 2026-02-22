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

    audio = Rack::MockRequest.new(file_app).get("/audio-file")
    expect(audio.status).to eq(200)
    expect(audio.headers["content-type"]).to include("audio")
    expect(audio.body.bytesize).to be > 0
  end
end
