# frozen_string_literal: true

require "tmpdir"
require "vizcore/cli/scene_inspector"
require "vizcore/cli/scene_validator"

RSpec.describe Vizcore::CLISupport::SceneValidator do
  around do |example|
    Vizcore::LayerCatalog.reset_plugin_capabilities!
    example.run
    Vizcore::LayerCatalog.reset_plugin_capabilities!
  end

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
            effect :bloom
            vj_effect :mirror
            map beat_confidence => :sync_strength
            map beat_pulse => :size
            map onset(:high) => :spark
            map kick => :pulse
            map hihat => :scatter
            map spectral_flux => :glitch
            map zero_crossing_rate => :noise
          end
        end

        transition from: :intro, to: :drop do
          trigger { beat_count >= 16 }
        end

        key "d" do
          switch_scene :drop
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
            map onset(:ultra) => :spark
          end
        end

        transition from: :broken, to: :missing

        key "m" do
          switch_scene :missing
        end
      end
    RUBY
      result = described_class.new(scene_file: scene_path).call
      messages = result.issues.map(&:message).join("\n")

      expect(result).not_to be_valid
      expect(messages).to include("unsupported type: unknown_visual")
      expect(messages).to include("unknown shader: missing_shader")
      expect(messages).to include("unsupported mapping source: mystery")
      expect(messages).to include("unsupported frequency band: :ultra")
      expect(messages).to include("unsupported onset band: :ultra")
      expect(messages).to include("unknown target scene: missing")
      expect(messages).to include("switches to unknown scene: missing")
      expect(result.warnings.map(&:message).join("\n")).to include("has no trigger block")
    end
  end

  it "accepts added shader presets" do
    with_scene_file(<<~RUBY) do |scene_path|
      Vizcore.define do
        scene :presets do
          layer(:crystal) { shader :ruby_crystal }
          layer(:stars) { shader :starfield }
          layer(:wave) { shader :waveform_ribbon }
        end
      end
    RUBY
      result = described_class.new(scene_file: scene_path).call

      expect(result).to be_valid
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

  it "reports unsupported layer effects" do
    with_scene_file(<<~RUBY) do |scene_path|
      Vizcore.define do
        scene :broken_effect do
          layer :visual do
            type :shader
            effect :unknown_post
            vj_effect :unknown_vj
          end
        end
      end
    RUBY
      result = described_class.new(scene_file: scene_path).call
      messages = result.errors.map(&:message).join("\n")

      expect(result).not_to be_valid
      expect(messages).to include("unsupported effect: unknown_post")
      expect(messages).to include("unsupported vj_effect: unknown_vj")
    end
  end

  it "warns about shape payloads that will be clamped or ignored" do
    with_scene_file(<<~RUBY) do |scene_path|
      Vizcore.define do
        scene :shape_warnings do
          layer :logo do
            type :shape
            shapes [
              {
                kind: :triangle,
                id: :badge,
                fill: "#ffffff",
                opacity: 1.5,
                transform: { scale: 0 }
              },
              {
                kind: :circle,
                id: :burst,
                scale: 12
              }
            ]
          end
        end
      end
    RUBY
      result = described_class.new(scene_file: scene_path).call
      messages = result.warnings.map(&:message).join("\n")

      expect(result).to be_valid
      expect(messages).to include("shape `badge` uses unsupported kind: triangle")
      expect(messages).to include("shape `badge` fill may be ignored by line fallback")
      expect(messages).to include("shape `badge` opacity 1.5 is outside 0..1; renderer will clamp")
      expect(messages).to include("shape `badge` scale includes 0; shape may collapse")
      expect(messages).to include("shape `burst` scale 12.0 is extreme; renderer will clamp")
    end
  end

  it "accepts supported layer post effects" do
    with_scene_file(<<~RUBY) do |scene_path|
      Vizcore.define do
        scene :effects do
          layer :blurred do
            type :shader
            effect :motion_blur
          end

          layer :retro do
            type :shader
            effect :crt
          end
        end
      end
    RUBY
      result = described_class.new(scene_file: scene_path).call

      expect(result).to be_valid
    end
  end

  it "uses layer capability metadata for supported type aliases" do
    with_scene_file(<<~RUBY) do |scene_path|
      Vizcore.define do
        scene :aliases do
          layer(:cube) { type :wireframe_cube }
          layer(:blob) { type :radial_blob }
          layer(:points) { type :particles }
          layer(:title) { type :text_layer }
          layer(:logo) { type :svg_layer }
          layer(:photo) { type :image_layer }
          layer(:footage) { type :video_layer }
          layer(:scope) { type :waveform_layer }
          layer(:waterfall) { type :spectrogram_layer }
          layer(:rings) { type :shape_layer }
          layer(:mesh) { type :mesh_layer }
        end
      end
    RUBY
      result = described_class.new(scene_file: scene_path).call

      expect(result).to be_valid
    end
  end

  it "accepts plugin layer capabilities registered after validator load" do
    Vizcore.register_layer_capability(
      type: :laser_grid,
      aliases: %i[laser_layer],
      params: { intensity: "Float" },
      mappable_params: %i[intensity],
      description: "Plugin laser layer."
    )

    with_scene_file(<<~RUBY) do |scene_path|
      Vizcore.define do
        scene :plugin do
          layer(:laser) { type :laser_layer }
        end
      end
    RUBY
      result = described_class.new(scene_file: scene_path).call

      expect(result).to be_valid
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

        key "i" do
          switch_scene :inspectable
        end
      end
    RUBY
      result = described_class.new(scene_file: scene_path).call
      lines = Vizcore::CLISupport::SceneInspector.new(definition: result.definition).lines

      expect(lines).to include("Audio:")
      expect(lines).to include("  inspectable")
      expect(lines).to include("    layer background (shader, shader=neon_grid)")
      expect(lines).to include("      amplitude -> intensity [gain=2.0]")
      expect(lines).to include("Keyboard:")
      expect(lines).to include("  i -> switch_scene inspectable")
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
