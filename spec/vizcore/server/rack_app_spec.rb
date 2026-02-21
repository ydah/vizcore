# frozen_string_literal: true

require "rack/mock"
require "vizcore/server/rack_app"

RSpec.describe Vizcore::Server::RackApp do
  subject(:app) { described_class.new(frontend_root: Vizcore.frontend_root) }

  it "serves the frontend entrypoint" do
    response = Rack::MockRequest.new(app).get("/")

    expect(response.status).to eq(200)
    expect(response.headers["content-type"]).to include("text/html")
    expect(response.body).to include("Vizcore Phase 0")
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
end
