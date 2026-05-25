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
          peak: 0.876543,
          bands: { low: 0.987654, high: 0.333333 },
          band_peaks: { low: 0.999999 },
          fft: [0.123456, 0.987654],
          onset: 0.234567,
          onsets: { high: 0.345678 },
          drums: { kick: 0.111111, snare: 0.222222, hihat: 0.333333 },
          beat: true,
          beat_confidence: 0.456789,
          beat_pulse: 0.765432,
          beat_count: 7,
          beat_phase: 0.234567,
          beat_2: true,
          beat_4: false,
          beat_8: true,
          beat_triplet: false,
          bar_phase: 0.567891,
          bar_count: 2,
          phrase_count: 1,
          bpm: 126.7,
          bpm_confidence: 0.555555,
          spectral_centroid: 1234.56789,
          spectral_rolloff: 4567.89123,
          spectral_flatness: 0.246813,
          spectral_flux: 0.135791,
          zero_crossing_rate: 0.02468,
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
      expect(frame[:schema_version]).to eq("vizcore.frame.v1")
      expect(frame[:audio]).to eq(
        amplitude: 0.1235,
        peak: 0.8765,
        bands: { low: 0.9877, high: 0.3333 },
        band_peaks: { sub: 0.0, low: 1.0, mid: 0.0, high: 0.0 },
        fft: [0.1235, 0.9877],
        onset: 0.2346,
        onsets: { sub: 0.0, low: 0.0, mid: 0.0, high: 0.3457 },
        drums: { kick: 0.1111, snare: 0.2222, hihat: 0.3333 },
        beat: true,
        beat_confidence: 0.4568,
        beat_pulse: 0.7654,
        beat_count: 7,
        beat_phase: 0.2346,
        beat_2: true,
        beat_4: false,
        beat_8: true,
        beat_triplet: false,
        bar_phase: 0.5679,
        bar_count: 2,
        phrase_count: 1,
        bpm: 126.7,
        bpm_confidence: 0.5556,
        spectral_centroid: 1234.5679,
        spectral_rolloff: 4567.8912,
        spectral_flatness: 0.2468,
        spectral_flux: 0.1358,
        zero_crossing_rate: 0.0247,
        peak_frequency: 440.1235
      )
      expect(frame[:scene]).to eq(
        schema_version: "vizcore.scene.v1",
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
