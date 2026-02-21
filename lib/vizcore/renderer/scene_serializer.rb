# frozen_string_literal: true

module Vizcore
  module Renderer
    class SceneSerializer
      def audio_frame(timestamp:, audio:, scene_name:, scene_layers:, transition: nil)
        {
          timestamp: Float(timestamp),
          audio: serialize_audio(audio),
          scene: serialize_scene(scene_name, scene_layers),
          transition: transition
        }
      end

      private

      def serialize_audio(audio)
        bands = symbolize_hash(audio[:bands])

        {
          amplitude: round_float(audio[:amplitude]),
          bands: bands.transform_values { |value| round_float(value) },
          fft: Array(audio[:fft]).map { |value| round_float(value) },
          beat: !!audio[:beat],
          beat_count: Integer(audio[:beat_count] || 0),
          bpm: audio[:bpm]
        }
      end

      def serialize_scene(scene_name, scene_layers)
        {
          name: scene_name.to_s,
          layers: Array(scene_layers).map { |layer| serialize_layer(layer) }
        }
      end

      def serialize_layer(layer)
        values = symbolize_hash(layer)

        output = {
          name: values.fetch(:name).to_s,
          type: (values[:type] || :geometry).to_s,
          params: symbolize_hash(values[:params])
        }
        output[:shader] = values[:shader].to_s if values[:shader]
        output[:glsl] = values[:glsl].to_s if values[:glsl]
        output
      end

      def symbolize_hash(value)
        Hash(value).each_with_object({}) do |(key, entry), output|
          output[key.to_sym] = entry
        end
      rescue StandardError
        {}
      end

      def round_float(value, digits: 4)
        Float(value).round(digits)
      rescue StandardError
        0.0
      end
    end
  end
end
