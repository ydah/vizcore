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
            { source: { kind: :beat }, target: :flash },
            { source: { kind: :beat_pulse }, target: :pulse },
            { source: { kind: :bpm }, target: :tempo }
          ]
        }
      ]
      audio = {
        amplitude: 0.72,
        bands: { sub: 0.1, low: 0.88, mid: 0.4, high: 0.2 },
        fft: Array.new(8, 0.05),
        beat: true,
        beat_pulse: 0.82,
        beat_count: 12,
        bpm: 128.5
      }

      resolved = resolver.resolve_layers(scene_layers: scene_layers, audio: audio)
      layer = resolved.fetch(0)

      expect(layer[:name]).to eq("background")
      expect(layer[:type]).to eq("shader")
      expect(layer[:shader]).to eq("gradient_pulse")
      expect(layer[:params]).to include(
        fixed: 1.0,
        intensity: 0.72,
        bass: 0.88,
        flash: true,
        pulse: 0.82,
        tempo: 128.5
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
  end
end
