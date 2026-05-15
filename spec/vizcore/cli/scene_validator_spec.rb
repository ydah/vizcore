# frozen_string_literal: true

require "tmpdir"
require "vizcore/cli/scene_inspector"
require "vizcore/cli/scene_validator"

RSpec.describe Vizcore::CLISupport::SceneValidator do
  it "validates a loadable scene with known layers, mappings, and transitions" do
    with_scene_file(<<~RUBY) do |scene_path|
      Vizcore.define do
        scene :intro do
          layer :background do
            shader :neon_grid
            map frequency_band(:low), to: :intensity, range: 0.2..1.0
          end
        end

        scene :drop do
          layer :particles do
            type :particle_field
            map beat_pulse => :size
          end
        end

        transition from: :intro, to: :drop do
          trigger { beat_count >= 16 }
        end
      end
    RUBY
      result = described_class.new(scene_file: scene_path).call

      expect(result).to be_valid
      expect(result.issues).to be_empty
    end
  end

  it "reports structural scene mistakes before server startup" do
    with_scene_file(<<~RUBY) do |scene_path|
      Vizcore.define do
        scene :broken do
          layer :bad do
            type :unknown_visual
            shader :missing_shader
            map :mystery => :speed
            map frequency_band(:ultra) => :size
          end
        end

        transition from: :broken, to: :missing
      end
    RUBY
      result = described_class.new(scene_file: scene_path).call
      messages = result.issues.map(&:message).join("\n")

      expect(result).not_to be_valid
      expect(messages).to include("unsupported type: unknown_visual")
      expect(messages).to include("unknown shader: missing_shader")
      expect(messages).to include("unsupported mapping source: mystery")
      expect(messages).to include("unsupported frequency band: :ultra")
      expect(messages).to include("unknown target scene: missing")
      expect(result.warnings.map(&:message).join("\n")).to include("has no trigger block")
    end
  end

  it "reports unsupported blend modes" do
    with_scene_file(<<~RUBY) do |scene_path|
      Vizcore.define do
        scene :broken_blend do
          layer :sparks do
            type :particle_field
            blend :overlay
          end
        end
      end
    RUBY
      result = described_class.new(scene_file: scene_path).call

      expect(result).not_to be_valid
      expect(result.errors.map(&:message).join("\n")).to include("unsupported blend mode: overlay")
    end
  end

  it "formats scene structure for inspection" do
    with_scene_file(<<~RUBY) do |scene_path|
      Vizcore.define do
        audio :mic, device: :default

        scene :inspectable do
          layer :background do
            shader :neon_grid
            map amplitude, to: :intensity, gain: 2.0
          end
        end
      end
    RUBY
      result = described_class.new(scene_file: scene_path).call
      lines = Vizcore::CLISupport::SceneInspector.new(definition: result.definition).lines

      expect(lines).to include("Audio:")
      expect(lines).to include("  inspectable")
      expect(lines).to include("    layer background (shader, shader=neon_grid)")
      expect(lines).to include("      amplitude -> intensity [gain=2.0]")
    end
  end

  def with_scene_file(body)
    Dir.mktmpdir("vizcore-scene-validator") do |dir|
      scene_path = File.join(dir, "scene.rb")
      File.write(scene_path, body)
      yield scene_path
    end
  end
end
