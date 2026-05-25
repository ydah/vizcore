# frozen_string_literal: true

require "vizcore/dsl/mapping_resolver"

RSpec.describe Vizcore::DSL::MappingResolver do
  describe "#resolve_layers" do
    it "applies mapping sources to layer params" do
      resolver = described_class.new
      scene_layers = [
        {
          name: :background,
          type: :shader,
          shader: :gradient_pulse,
          params: { fixed: 1.0 },
          mappings: [
            { source: { kind: :amplitude }, target: :intensity },
            { source: { kind: :frequency_band, band: :low }, target: :bass },
            { source: { kind: :frequency_band_peak, band: :low }, target: :bass_peak },
            { source: { kind: :beat }, target: :flash },
            { source: { kind: :beat_confidence }, target: :sync_strength },
            { source: { kind: :beat_pulse }, target: :pulse },
            { source: { kind: :beat_phase }, target: :phase },
            { source: { kind: :beat_2 }, target: :half_step },
            { source: { kind: :beat_4 }, target: :quarter_step },
            { source: { kind: :beat_8 }, target: :eighth_step },
            { source: { kind: :beat_triplet }, target: :triplet_step },
            { source: { kind: :bar_phase }, target: :bar_loop },
            { source: { kind: :bar_count }, target: :bars },
            { source: { kind: :phrase_count }, target: :phrases },
            { source: { kind: :onset }, target: :burst },
            { source: { kind: :onset, band: :high }, target: :spark },
            { source: { kind: :kick }, target: :kick_flash },
            { source: { kind: :hihat }, target: :hihat_scatter },
            { source: { kind: :bpm }, target: :tempo },
            { source: { kind: :peak }, target: :peak_level },
            { source: { kind: :bpm_confidence }, target: :tempo_lock },
            { source: { kind: :spectral_centroid }, target: :brightness },
            { source: { kind: :spectral_rolloff }, target: :rolloff },
            { source: { kind: :spectral_flatness }, target: :noise },
            { source: { kind: :spectral_flux }, target: :flux },
            { source: { kind: :zero_crossing_rate }, target: :crossings },
            { source: { kind: :global, name: :intensity }, target: :global_intensity }
          ]
        }
      ]
      audio = {
        amplitude: 0.72,
        peak: 0.95,
        bands: { sub: 0.1, low: 0.88, mid: 0.4, high: 0.2 },
        band_peaks: { low: 0.92 },
        fft: Array.new(8, 0.05),
        beat: true,
        beat_confidence: 0.64,
        beat_pulse: 0.82,
        beat_phase: 0.25,
        beat_2: true,
        beat_4: false,
        beat_8: true,
        beat_triplet: false,
        bar_phase: 0.5625,
        bar_count: 3,
        phrase_count: 1,
        onset: 0.31,
        onsets: { high: 0.44 },
        drums: { kick: 0.51, hihat: 0.29 },
        beat_count: 12,
        bpm: 128.5,
        bpm_confidence: 0.7,
        spectral_centroid: 1_200.0,
        spectral_rolloff: 4_500.0,
        spectral_flatness: 0.33,
        spectral_flux: 0.27,
        zero_crossing_rate: 0.08
      }

      resolved = resolver.resolve_layers(scene_layers: scene_layers, audio: audio, globals: { intensity: 0.66 })
      layer = resolved.fetch(0)

      expect(layer[:name]).to eq("background")
      expect(layer[:type]).to eq("shader")
      expect(layer[:shader]).to eq("gradient_pulse")
      expect(layer[:params]).to include(
        fixed: 1.0,
        intensity: 0.72,
        bass: 0.88,
        bass_peak: 0.92,
        flash: true,
        sync_strength: 0.64,
        pulse: 0.82,
        phase: 0.25,
        half_step: true,
        quarter_step: false,
        eighth_step: true,
        triplet_step: false,
        bar_loop: 0.5625,
        bars: 3,
        phrases: 1,
        burst: 0.31,
        spark: 0.44,
        kick_flash: 0.51,
        hihat_scatter: 0.29,
        tempo: 128.5,
        peak_level: 0.95,
        tempo_lock: 0.7,
        brightness: 1_200.0,
        rolloff: 4_500.0,
        noise: 0.33,
        flux: 0.27,
        crossings: 0.08,
        global_intensity: 0.66
      )
    end

    it "preserves custom shader source payload for frontend compilation" do
      resolver = described_class.new
      scene_layers = [
        {
          name: :wave_shader,
          type: :shader,
          glsl: "shaders/custom_wave.frag",
          glsl_source: "void main() { }",
          params: {}
        }
      ]

      resolved = resolver.resolve_layers(scene_layers: scene_layers, audio: { bands: {} })
      layer = resolved.fetch(0)

      expect(layer[:glsl]).to eq("shaders/custom_wave.frag")
      expect(layer[:glsl_source]).to eq("void main() { }")
    end

    it "preserves shader parameter schema metadata" do
      resolver = described_class.new
      scene_layers = [
        {
          name: :liquid,
          type: :shader,
          params: { wobble: 0.3 },
          param_schema: [{ name: :wobble, default: 0.3, min: 0.0, max: 2.0, step: 0.05 }]
        }
      ]

      resolved = resolver.resolve_layers(scene_layers: scene_layers, audio: { bands: {} })

      expect(resolved.fetch(0)[:param_schema]).to eq(
        [{ name: :wobble, default: 0.3, min: 0.0, max: 2.0, step: 0.05 }]
      )
    end

    it "ignores unknown mapping source kinds" do
      resolver = described_class.new
      scene_layers = [
        {
          name: :layer,
          params: {},
          mappings: [{ source: { kind: :unknown }, target: :value }]
        }
      ]

      resolved = resolver.resolve_layers(scene_layers: scene_layers, audio: { bands: {} })
      expect(resolved[0][:params]).to eq({})
    end

    it "applies mapping gain range and curve" do
      resolver = described_class.new
      scene_layers = [
        {
          name: :liquid,
          params: {},
          mappings: [
            {
              source: { kind: :amplitude },
              target: :wobble,
              transform: { gain: 4.0, min: 0.1, max: 1.0, curve: :sqrt }
            }
          ]
        }
      ]

      resolved = resolver.resolve_layers(scene_layers: scene_layers, audio: { amplitude: 0.0625, bands: {} })

      expect(resolved[0][:params][:wobble]).to eq(0.5)
    end

    it "applies mapping deadzone and ease_out curve" do
      resolver = described_class.new
      scene_layers = [
        {
          name: :liquid,
          params: {},
          mappings: [
            {
              source: { kind: :amplitude },
              target: :wobble,
              transform: { deadzone: 0.05, curve: :ease_out }
            }
          ]
        }
      ]

      quiet = resolver.resolve_layers(scene_layers: scene_layers, audio: { amplitude: 0.04, bands: {} })
      active = resolver.resolve_layers(scene_layers: scene_layers, audio: { amplitude: 0.5, bands: {} })

      expect(quiet[0][:params][:wobble]).to eq(0.0)
      expect(active[0][:params][:wobble]).to eq(0.75)
    end

    it "applies additional curves" do
      resolver = described_class.new
      curves = {
        ease_in: 0.25,
        ease_in_out: 0.5,
        smoothstep: 0.5,
        step: 1.0
      }
      scene_layers = [
        {
          name: :curves,
          params: {},
          mappings: curves.keys.map do |curve|
            { source: { kind: :amplitude }, target: curve, transform: { curve: curve } }
          end
        }
      ]

      resolved = resolver.resolve_layers(scene_layers: scene_layers, audio: { amplitude: 0.5, bands: {} })

      curves.each do |target, expected|
        expect(resolved[0][:params][target]).to be_within(0.0001).of(expected)
      end
    end

    it "applies threshold hysteresis hold and decay transforms" do
      resolver = described_class.new
      scene_layers = [
        {
          name: :triggered,
          params: {},
          mappings: [
            {
              source: { kind: :spectral_flux },
              target: :flash,
              transform: { threshold: 0.5, hysteresis: 0.1, hold: 0.05, decay: 0.5 }
            }
          ]
        }
      ]

      high = resolver.resolve_layers(scene_layers: scene_layers, audio: { spectral_flux: 0.6, bands: {} }, frame: 1)
      held = resolver.resolve_layers(scene_layers: scene_layers, audio: { spectral_flux: 0.0, bands: {} }, frame: 3)
      decayed = resolver.resolve_layers(scene_layers: scene_layers, audio: { spectral_flux: 0.0, bands: {} }, frame: 10)

      expect(high[0][:params][:flash]).to eq(0.6)
      expect(held[0][:params][:flash]).to eq(0.6)
      expect(decayed[0][:params][:flash]).to eq(0.3)
    end

    it "applies square curve after gain and before range clamping" do
      resolver = described_class.new
      scene_layers = [
        {
          name: :liquid,
          params: {},
          mappings: [
            {
              source: { kind: :amplitude },
              target: :pulse,
              transform: { gain: 1.2, min: 0.2, max: 0.8, curve: :square }
            }
          ]
        }
      ]

      resolved = resolver.resolve_layers(scene_layers: scene_layers, audio: { amplitude: 0.5, bands: {} })

      expect(resolved[0][:params][:pulse]).to be_within(0.0001).of(0.36)
    end

    it "converts boolean sources when applying transforms" do
      resolver = described_class.new
      scene_layers = [
        {
          name: :flash,
          params: {},
          mappings: [
            {
              source: { kind: :beat },
              target: :intensity,
              transform: { gain: 0.5, min: 0.0, max: 1.0 }
            }
          ]
        }
      ]

      resolved = resolver.resolve_layers(scene_layers: scene_layers, audio: { beat: true, bands: {} })

      expect(resolved[0][:params][:intensity]).to eq(0.5)
    end

    it "applies attack and release smoothing across calls" do
      resolver = described_class.new
      scene_layers = [
        {
          name: :smooth,
          params: {},
          mappings: [
            {
              source: { kind: :amplitude },
              target: :wobble,
              transform: { attack: 1.0, release: 0.5 }
            }
          ]
        }
      ]

      first = resolver.resolve_layers(scene_layers: scene_layers, audio: { amplitude: 1.0, bands: {} })
      second = resolver.resolve_layers(scene_layers: scene_layers, audio: { amplitude: 0.0, bands: {} })

      expect(first[0][:params][:wobble]).to eq(1.0)
      expect(second[0][:params][:wobble]).to eq(0.5)
    end

    it "keeps smoothing state isolated by mapping target" do
      resolver = described_class.new
      scene_layers = [
        {
          name: :smooth,
          params: {},
          mappings: [
            {
              source: { kind: :amplitude },
              target: :slow,
              transform: { attack: 1.0, release: 0.2 }
            },
            {
              source: { kind: :amplitude },
              target: :fast,
              transform: { attack: 1.0, release: 0.8 }
            }
          ]
        }
      ]

      resolver.resolve_layers(scene_layers: scene_layers, audio: { amplitude: 1.0, bands: {} })
      resolved = resolver.resolve_layers(scene_layers: scene_layers, audio: { amplitude: 0.0, bands: {} })

      expect(resolved[0][:params][:slow]).to be_within(0.0001).of(0.8)
      expect(resolved[0][:params][:fast]).to be_within(0.0001).of(0.2)
    end

    it "applies transform options to array values without smoothing" do
      resolver = described_class.new
      scene_layers = [
        {
          name: :blob,
          params: {},
          mappings: [
            {
              source: { kind: :fft_spectrum },
              target: :spectrum,
              transform: { gain: 2.0, min: 0.0, max: 1.0 }
            }
          ]
        }
      ]

      resolved = resolver.resolve_layers(
        scene_layers: scene_layers,
        audio: { fft: [0.3, 0.8, "bad", -0.2], bands: {} }
      )

      expect(resolved[0][:params][:spectrum]).to eq([0.6, 1.0, 0.0, 0.0])
    end

    it "applies mappings to nested shape params" do
      resolver = described_class.new
      scene_layers = [
        {
          name: :rings,
          type: :shape,
          params: {
            shapes: [
              { kind: :circle, radius: 100 }
            ]
          },
          mappings: [
            {
              source: { kind: :frequency_band, band: :low },
              target: :"shapes.0.radius",
              transform: { min: 40.0, max: 180.0 }
            },
            {
              source: { kind: :amplitude },
              target: :"shapes.0.transform.translate.x",
              transform: { gain: 100.0 }
            }
          ]
        }
      ]

      resolved = resolver.resolve_layers(scene_layers: scene_layers, audio: { amplitude: 0.25, bands: { low: 0.8 } })

      expect(resolved[0][:params][:shapes][0][:radius]).to eq(40.0)
      expect(resolved[0][:params][:shapes][0][:transform]).to eq(translate: { x: 25.0 })
    end

    it "applies layer parameter overrides after audio mappings" do
      resolver = described_class.new
      scene_layers = [
        {
          name: :rings,
          params: { opacity: 0.3, transform: { scale: { x: 1.0 } } },
          mappings: [{ source: { kind: :amplitude }, target: :opacity }]
        }
      ]

      resolved = resolver.resolve_layers(
        scene_layers: scene_layers,
        audio: { amplitude: 0.8, bands: {} },
        layer_param_overrides: { "rings" => { "opacity" => 0.5, "transform.scale.x" => 1.5 } }
      )

      expect(resolved[0][:params]).to include(opacity: 0.5)
      expect(resolved[0][:params].dig(:transform, :scale, :x)).to eq(1.5)
    end

    it "expands dynamic custom shapes after custom params are mapped" do
      shape_class = Class.new do
        include Vizcore::Shape

        def draw(ctx)
          {
            kind: :circle,
            radius: ctx.param(:radius),
            opacity: ctx.audio.high
          }
        end
      end
      resolver = described_class.new
      scene_layers = [
        {
          name: :generated,
          type: :shape,
          params: {
            custom_shapes: [
              {
                name: :dynamic_circle,
                renderer: shape_class,
                params: { radius: 10 },
                style: { fill: "#22d3ee", opacity: 0.5 },
                transform: { scale: 1.2 },
                dynamic: true
              }
            ]
          },
          mappings: [
            {
              source: { kind: :amplitude },
              target: :"custom_shapes.0.params.radius",
              transform: { gain: 100.0 }
            },
            {
              source: { kind: :frequency_band, band: :high },
              target: :"custom_shapes.0.transform.translate.x",
              transform: { gain: 10.0 }
            }
          ]
        }
      ]

      resolved = resolver.resolve_layers(
        scene_layers: scene_layers,
        audio: { amplitude: 0.4, bands: { high: 0.8 } },
        time: 2.0,
        frame: 7
      )

      expect(resolved[0][:params]).not_to have_key(:custom_shapes)
      expect(resolved[0][:params][:shapes]).to eq(
        [
          {
            kind: :circle,
            radius: 40.0,
            opacity: 0.4,
            fill: "#22d3ee",
            transform: { scale: 1.2, translate: { x: 8.0 } }
          }
        ]
      )
      expect(resolved[0][:params][:custom_shape_controls]).to eq(
        [
          {
            index: 0,
            name: "dynamic_circle",
            params: { radius: 40.0 },
            param_schema: [],
            shape_indices: [0]
          }
        ]
      )
    end

    it "applies dynamic custom shape param overrides before expansion" do
      shape_class = Class.new do
        include Vizcore::Shape

        param :radius, default: 10, min: 1, max: 200

        def draw(ctx)
          { kind: :circle, radius: ctx.param(:radius) }
        end
      end
      resolver = described_class.new
      scene_layers = [
        {
          name: :generated,
          type: :shape,
          params: {
            custom_shapes: [
              {
                name: :dynamic_circle,
                renderer: shape_class,
                params: { radius: 10 },
                param_schema: shape_class.shape_param_schema.values,
                dynamic: true
              }
            ]
          }
        }
      ]

      resolved = resolver.resolve_layers(
        scene_layers: scene_layers,
        audio: {},
        custom_shape_overrides: { "generated" => { 0 => { "radius" => 72 } } }
      )

      expect(resolved[0][:params][:shapes]).to eq([{ kind: :circle, radius: 72.0 }])
      expect(resolved[0][:params][:custom_shape_controls]).to contain_exactly(
        hash_including(
          index: 0,
          name: "dynamic_circle",
          params: { radius: 72 },
          param_schema: [{ name: :radius, default: 10, min: 1, max: 200 }],
          shape_indices: [0]
        )
      )
    end
  end
end
