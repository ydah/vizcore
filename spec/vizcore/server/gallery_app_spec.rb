# frozen_string_literal: true

require "json"
require "fileutils"
require "rack/mock"
require "tmpdir"
require "vizcore/server/gallery_app"

RSpec.describe Vizcore::Server::GalleryApp do
  it "serves an HTML gallery for example scenes" do
    Dir.mktmpdir("vizcore-gallery-app") do |dir|
      examples_root = File.join(dir, "examples")
      assets_root = File.join(dir, "assets")
      FileUtils.mkdir_p(assets_root)
      write_example(examples_root, "basic.rb", :basic)
      File.binwrite(File.join(assets_root, "vizcore-poster.png"), "PNG")

      app = described_class.new(examples_root: examples_root, docs_assets_root: assets_root)
      response = Rack::MockRequest.new(app).get("/")

      expect(response.status).to eq(200)
      expect(response.headers["content-type"]).to include("text/html")
      expect(response.body).to include("Example Gallery")
      expect(response.body).to include("basic")
      expect(response.body).to include("vizcore start")
    end
  end

  it "serves example metadata as json" do
    Dir.mktmpdir("vizcore-gallery-json") do |dir|
      examples_root = File.join(dir, "examples")
      write_example(examples_root, "file_audio_demo.rb", :groove)

      app = described_class.new(examples_root: examples_root, docs_assets_root: File.join(dir, "missing-assets"))
      response = Rack::MockRequest.new(app).get("/examples.json")
      payload = JSON.parse(response.body)
      example = payload.fetch("examples").first

      expect(response.status).to eq(200)
      expect(example.fetch("file")).to end_with("file_audio_demo.rb")
      expect(example.fetch("scene_names")).to eq(["groove"])
      expect(example.fetch("audio_source")).to eq("file")
      expect(example.fetch("command")).to include("--audio-file")
    end
  end

  it "serves the gallery poster asset when present" do
    Dir.mktmpdir("vizcore-gallery-asset") do |dir|
      assets_root = File.join(dir, "assets")
      FileUtils.mkdir_p(assets_root)
      File.binwrite(File.join(assets_root, "vizcore-poster.png"), "PNG")

      app = described_class.new(examples_root: File.join(dir, "examples"), docs_assets_root: assets_root)
      response = Rack::MockRequest.new(app).get("/assets/vizcore-poster.png")

      expect(response.status).to eq(200)
      expect(response.headers["content-type"]).to eq("image/png")
      expect(response.body).to eq("PNG")
    end
  end

  def write_example(root, file_name, scene_name)
    FileUtils.mkdir_p(root)
    File.write(
      File.join(root, file_name),
      <<~RUBY
        Vizcore.define do
          scene #{scene_name.inspect} do
            layer :shape do
              type :wireframe_cube
            end
          end
        end
      RUBY
    )
  end
end
