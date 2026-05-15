# frozen_string_literal: true

require "base64"
require "tmpdir"
require "fileutils"
require "vizcore/dsl/shader_source_resolver"

RSpec.describe Vizcore::DSL::ShaderSourceResolver do
  it "embeds glsl source into layer definition relative to scene file" do
    Dir.mktmpdir("vizcore-shader-resolver") do |dir|
      scene_path = File.join(dir, "scene.rb")
      shader_path = File.join(dir, "shaders", "custom.frag")
      FileUtils.mkdir_p(File.dirname(shader_path))
      File.write(scene_path, "Vizcore.define {}")
      File.write(shader_path, "void main() { }")

      definition = {
        scenes: [
          {
            name: :intro,
            layers: [
              { name: :shader_art, type: :shader, glsl: "shaders/custom.frag", params: {} }
            ]
          }
        ]
      }

      resolved = described_class.new.resolve(definition: definition, scene_file: scene_path)
      layer = resolved.dig(:scenes, 0, :layers, 0)

      expect(layer[:glsl]).to eq("shaders/custom.frag")
      expect(layer[:glsl_source]).to eq("void main() { }")
    end
  end

  it "raises when glsl path is missing" do
    Dir.mktmpdir("vizcore-shader-resolver") do |dir|
      scene_path = File.join(dir, "scene.rb")
      File.write(scene_path, "Vizcore.define {}")

      definition = {
        scenes: [
          {
            name: :intro,
            layers: [{ name: :shader_art, type: :shader, glsl: "missing.frag" }]
          }
        ]
      }

      expect do
        described_class.new.resolve(definition: definition, scene_file: scene_path)
      end.to raise_error(ArgumentError, /GLSL file not found/)
    end
  end

  it "embeds svg files into layer params relative to scene file" do
    Dir.mktmpdir("vizcore-svg-resolver") do |dir|
      scene_path = File.join(dir, "scene.rb")
      svg_path = File.join(dir, "assets", "logo.svg")
      FileUtils.mkdir_p(File.dirname(svg_path))
      File.write(scene_path, "Vizcore.define {}")
      File.write(svg_path, "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>")

      definition = {
        scenes: [
          {
            name: :intro,
            layers: [
              { name: :logo, type: :svg, params: { file: "assets/logo.svg" } }
            ]
          }
        ]
      }

      resolved = described_class.new.resolve(definition: definition, scene_file: scene_path)
      params = resolved.dig(:scenes, 0, :layers, 0, :params)

      expect(params[:file]).to eq("assets/logo.svg")
      expect(params[:src]).to start_with("data:image/svg+xml;base64,")
    end
  end

  it "raises when svg path is missing" do
    Dir.mktmpdir("vizcore-svg-resolver") do |dir|
      scene_path = File.join(dir, "scene.rb")
      File.write(scene_path, "Vizcore.define {}")

      definition = {
        scenes: [
          {
            name: :intro,
            layers: [{ name: :logo, type: :svg, params: { file: "missing.svg" } }]
          }
        ]
      }

      expect do
        described_class.new.resolve(definition: definition, scene_file: scene_path)
      end.to raise_error(ArgumentError, /SVG file not found/)
    end
  end

  it "embeds image files into layer params relative to scene file" do
    Dir.mktmpdir("vizcore-image-resolver") do |dir|
      scene_path = File.join(dir, "scene.rb")
      image_path = File.join(dir, "assets", "noise.png")
      FileUtils.mkdir_p(File.dirname(image_path))
      File.write(scene_path, "Vizcore.define {}")
      File.binwrite(image_path, Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADggGAdi8ccQAAAABJRU5ErkJggg=="))

      definition = {
        scenes: [
          {
            name: :intro,
            layers: [
              { name: :photo, type: :image, params: { file: "assets/noise.png" } }
            ]
          }
        ]
      }

      resolved = described_class.new.resolve(definition: definition, scene_file: scene_path)
      params = resolved.dig(:scenes, 0, :layers, 0, :params)

      expect(params[:file]).to eq("assets/noise.png")
      expect(params[:src]).to start_with("data:image/png;base64,")
    end
  end

  it "embeds video files into layer params relative to scene file" do
    Dir.mktmpdir("vizcore-video-resolver") do |dir|
      scene_path = File.join(dir, "scene.rb")
      video_path = File.join(dir, "assets", "loop.mp4")
      FileUtils.mkdir_p(File.dirname(video_path))
      File.write(scene_path, "Vizcore.define {}")
      File.binwrite(video_path, "fake mp4 bytes")

      definition = {
        scenes: [
          {
            name: :intro,
            layers: [
              { name: :footage, type: :video, params: { file: "assets/loop.mp4" } }
            ]
          }
        ]
      }

      resolved = described_class.new.resolve(definition: definition, scene_file: scene_path)
      params = resolved.dig(:scenes, 0, :layers, 0, :params)

      expect(params[:file]).to eq("assets/loop.mp4")
      expect(params[:src]).to start_with("data:video/mp4;base64,")
    end
  end

  it "raises when image extension is unsupported" do
    Dir.mktmpdir("vizcore-image-resolver") do |dir|
      scene_path = File.join(dir, "scene.rb")
      image_path = File.join(dir, "assets", "noise.txt")
      FileUtils.mkdir_p(File.dirname(image_path))
      File.write(scene_path, "Vizcore.define {}")
      File.write(image_path, "not an image")

      definition = {
        scenes: [
          {
            name: :intro,
            layers: [{ name: :photo, type: :image, params: { file: "assets/noise.txt" } }]
          }
        ]
      }

      expect do
        described_class.new.resolve(definition: definition, scene_file: scene_path)
      end.to raise_error(ArgumentError, /Unsupported Image file extension/)
    end
  end

  it "raises when video extension is unsupported" do
    Dir.mktmpdir("vizcore-video-resolver") do |dir|
      scene_path = File.join(dir, "scene.rb")
      video_path = File.join(dir, "assets", "loop.txt")
      FileUtils.mkdir_p(File.dirname(video_path))
      File.write(scene_path, "Vizcore.define {}")
      File.write(video_path, "not video")

      definition = {
        scenes: [
          {
            name: :intro,
            layers: [{ name: :footage, type: :video, params: { file: "assets/loop.txt" } }]
          }
        ]
      }

      expect do
        described_class.new.resolve(definition: definition, scene_file: scene_path)
      end.to raise_error(ArgumentError, /Unsupported Video file extension/)
    end
  end
end
