# frozen_string_literal: true

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
end
