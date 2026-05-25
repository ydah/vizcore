# frozen_string_literal: true

module Vizcore
  module Renderer
    # Serializes analysis and scene state into transport payloads.
    class SceneSerializer
      SCENE_SCHEMA_VERSION = "vizcore.scene.v1"
      FRAME_SCHEMA_VERSION = "vizcore.frame.v1"

      # @param timestamp [Numeric]
      # @param audio [Hash]
      # @param scene_name [String, Symbol]
      # @param scene_layers [Array<Hash>]
      # @param transition [Hash, nil]
      # @param metrics [Hash, nil]
      # @return [Hash]
      def audio_frame(timestamp:, audio:, scene_name:, scene_layers:, transition: nil, metrics: nil)
        frame = {
          schema_version: FRAME_SCHEMA_VERSION,
          timestamp: Float(timestamp),
          audio: serialize_audio(audio),
          scene: serialize_scene(scene_name, scene_layers),
          transition: transition
        }
        frame[:metrics] = serialize_metrics(metrics) if metrics
        frame
      end

      private

      def serialize_audio(audio)
        bands = symbolize_hash(audio[:bands])
        onsets = { sub: 0.0, low: 0.0, mid: 0.0, high: 0.0 }.merge(symbolize_hash(audio[:onsets]))
        drums = { kick: 0.0, snare: 0.0, hihat: 0.0 }.merge(symbolize_hash(audio[:drums]))

        {
          amplitude: round_float(audio[:amplitude]),
          bands: bands.transform_values { |value| round_float(value) },
          fft: Array(audio[:fft]).map { |value| round_float(value) },
          onset: round_float(audio[:onset]),
          onsets: onsets.transform_values { |value| round_float(value) },
          drums: drums.transform_values { |value| round_float(value) },
          beat: !!audio[:beat],
          beat_confidence: round_float(audio[:beat_confidence]),
          beat_pulse: round_float(audio[:beat_pulse]),
          beat_count: Integer(audio[:beat_count] || 0),
          bpm: audio[:bpm],
          peak_frequency: round_float(audio[:peak_frequency])
        }
      end

      def serialize_scene(scene_name, scene_layers)
        {
          schema_version: SCENE_SCHEMA_VERSION,
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
        output[:glsl_source] = values[:glsl_source].to_s if values[:glsl_source]
        output[:param_schema] = serialize_param_schema(values[:param_schema]) if values[:param_schema]
        output
      end

      def serialize_param_schema(schema)
        Array(schema).map do |entry|
          values = symbolize_hash(entry)
          {
            name: values.fetch(:name).to_s,
            default: round_float(values[:default]),
            min: round_float(values[:min]),
            max: round_float(values[:max]),
            step: round_float(values[:step])
          }.compact
        end
      end

      def serialize_metrics(metrics)
        symbolize_hash(metrics).each_with_object({}) do |(key, value), output|
          output[key] = key == :frame_id ? Integer(value) : round_float(value)
        rescue StandardError
          output[key] = 0
        end
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
