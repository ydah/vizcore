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
            { source: { kind: :bpm }, target: :tempo }
          ]
        }
      ]
      audio = {
        amplitude: 0.72,
        bands: { sub: 0.1, low: 0.88, mid: 0.4, high: 0.2 },
        fft: Array.new(8, 0.05),
        beat: true,
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
  end
end
