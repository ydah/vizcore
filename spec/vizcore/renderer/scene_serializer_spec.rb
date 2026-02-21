# frozen_string_literal: true

require "vizcore/renderer/scene_serializer"

RSpec.describe Vizcore::Renderer::SceneSerializer do
  describe "#audio_frame" do
    it "serializes audio and scene payload into audio_frame shape" do
      serializer = described_class.new
      frame = serializer.audio_frame(
        timestamp: 1.23456,
        audio: {
          amplitude: 0.123456,
          bands: { low: 0.987654, high: 0.333333 },
          fft: [0.123456, 0.987654],
          beat: true,
          beat_count: 7,
          bpm: 126.7
        },
        scene_name: :intro,
        scene_layers: [
          {
            name: :background,
            type: :shader,
            shader: :gradient_pulse,
            glsl: "shaders/custom_wave.frag",
            glsl_source: "void main() { }",
            params: { intensity: 0.5 }
          }
        ]
      )

      expect(frame[:timestamp]).to eq(1.23456)
      expect(frame[:audio]).to eq(
        amplitude: 0.1235,
        bands: { low: 0.9877, high: 0.3333 },
        fft: [0.1235, 0.9877],
        beat: true,
        beat_count: 7,
        bpm: 126.7
      )
      expect(frame[:scene]).to eq(
        name: "intro",
        layers: [
          {
            name: "background",
            type: "shader",
            shader: "gradient_pulse",
            glsl: "shaders/custom_wave.frag",
            glsl_source: "void main() { }",
            params: { intensity: 0.5 }
          }
        ]
      )
      expect(frame[:transition]).to be_nil
    end
  end
end
