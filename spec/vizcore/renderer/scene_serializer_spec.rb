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
          beat_confidence: 0.456789,
          beat_pulse: 0.765432,
          beat_count: 7,
          bpm: 126.7,
          peak_frequency: 440.12345
        },
        scene_name: :intro,
        scene_layers: [
          {
            name: :background,
            type: :shader,
            shader: :gradient_pulse,
            glsl: "shaders/custom_wave.frag",
            glsl_source: "void main() { }",
            params: { intensity: 0.5 },
            param_schema: [{ name: :intensity, default: 0.5, min: 0.0, max: 2.0, step: 0.1 }]
          }
        ],
        metrics: {
          frame_id: 12,
          audio_capture_ms: 0.12345,
          audio_analysis_ms: 1.98765
        }
      )

      expect(frame[:timestamp]).to eq(1.23456)
      expect(frame[:audio]).to eq(
        amplitude: 0.1235,
        bands: { low: 0.9877, high: 0.3333 },
        fft: [0.1235, 0.9877],
        beat: true,
        beat_confidence: 0.4568,
        beat_pulse: 0.7654,
        beat_count: 7,
        bpm: 126.7,
        peak_frequency: 440.1235
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
            params: { intensity: 0.5 },
            param_schema: [
              {
                name: "intensity",
                default: 0.5,
                min: 0.0,
                max: 2.0,
                step: 0.1
              }
            ]
          }
        ]
      )
      expect(frame[:transition]).to be_nil
      expect(frame[:metrics]).to eq(
        frame_id: 12,
        audio_capture_ms: 0.1235,
        audio_analysis_ms: 1.9877
      )
    end
  end
end
