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
            map global(:intensity) => :opacity
            map lfo(:sine, rate: 0.5) => :drift
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
            map({ kind: :global }, to: :opacity)
            map({ kind: :lfo, wave: :random, rate: :fast }, to: :drift)
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
      expect(result.errors.map(&:code)).to include(
        "E_UNKNOWN_LAYER_TYPE",
        "E_UNKNOWN_SHADER",
        "E_UNKNOWN_MAPPING_SOURCE",
        "E_UNKNOWN_FREQUENCY_BAND",
        "E_UNKNOWN_ONSET_BAND",
        "E_GLOBAL_SOURCE_NAME",
        "E_LFO_WAVE",
        "E_LFO_RATE",
        "E_UNKNOWN_TRANSITION_TARGET",
        "E_UNKNOWN_KEY_SCENE"
      )
      expect(messages).to include("unsupported type: unknown_visual")
      expect(messages).to include("unknown shader: missing_shader")
      expect(messages).to include("unsupported mapping source: mystery")
      expect(messages).to include("unsupported frequency band: :ultra")
      expect(messages).to include("unsupported onset band: :ultra")
      expect(messages).to include("unsupported LFO wave: random")
      expect(messages).to include("non-numeric LFO rate: fast")
      expect(messages).to include("unknown target scene: missing")
      expect(messages).to include("switches to unknown scene: missing")
      expect(result.warnings.map(&:message).join("\n")).to include("has no trigger block")
      expect(result.warnings.map(&:code)).to include("W_TRANSITION_WITHOUT_TRIGGER")
    end
  end

  it "rejects unsupported mapping as mode" do
    with_scene_file(<<~RUBY) do |scene_path|
      Vizcore.define do
        scene :bad_map do
          layer :source do
            type :shape
            map amplitude, to: :radius, as: :glow
          end
        end
      end
    RUBY
      result = described_class.new(scene_file: scene_path).call

      expect(result).not_to be_valid
      expect(result.errors.map(&:code)).to include("E_SCENE_LOAD")
      expect(result.errors.map(&:message).join("\n")).to include("unsupported mapping mode: :glow")
    end

    validator = described_class.new(scene_file: __FILE__)
    issues = []
    validator.send(:validate_transform, { as: :glow }, "scene", "layer", "target", issues)

    expect(issues.map(&:code)).to include("E_MAPPING_TRANSFORM_AS")
    expect(issues.map(&:message).join("\n")).to include("unsupported as mode: glow")
  end

  it "reports strict unknown params and duplicate control bindings" do
    with_scene_file(<<~RUBY) do |scene_path|
      Vizcore.define do
        scene :broken do
          layer :shape_layer do
            type :shape
            opactiy 0.7
            shapes [
              { kind: :circle, id: :dot },
              { kind: :circle, id: :dot }
            ]
            map amplitude => :opacity
            map peak => :opacity
            map beat_pulse => :"shapes.3.radius"
          end
        end

        key "x" do
          freeze
        end

        key "x" do
          blackout
        end

        midi_map note: 36 do
          switch_scene :broken
        end

        midi_map note: 36 do
          switch_scene :broken
        end
      end
    RUBY
      result = described_class.new(scene_file: scene_path, strict: true).call
      codes = result.issues.map(&:code)

      expect(result).not_to be_valid
      expect(codes).to include(
        "E_UNKNOWN_LAYER_PARAM",
        "E_DUPLICATE_SHAPE",
        "W_DUPLICATE_MAPPING_TARGET",
        "E_MAPPING_TARGET",
        "E_DUPLICATE_KEY_MAPPING",
        "E_DUPLICATE_MIDI_MAPPING"
      )
    end
  end

  it "flags MIDI actions that switch to unknown scenes" do
    with_scene_file(<<~RUBY) do |scene_path|
      Vizcore.define do
        scene :known do
          layer :shape do
            type :shape
          end
        end

        midi_map note: 36 do
          switch_scene :missing_scene
        end

        midi_map pc: 9 do |value|
          if value.zero?
            blackout
          else
            switch_scene :also_missing
          end
        end
      end
    RUBY
      result = described_class.new(scene_file: scene_path).call
      messages = result.issues.map(&:message)

      expect(result).not_to be_valid
      expect(result.issues.map(&:code)).to include("E_UNKNOWN_MIDI_SCENE")
      expect(messages).to include("MIDI mapping switches to unknown scene: missing_scene")
      expect(messages).to include("MIDI mapping switches to unknown scene: also_missing")
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
            map global(:intensity) => :opacity
            map lfo(:triangle, rate: 0.5, phase: 0.25) => :drift
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
      expect(lines).to include("      global(intensity) -> opacity")
      expect(lines).to include("      lfo(triangle, rate=0.5, phase=0.25) -> drift")
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
