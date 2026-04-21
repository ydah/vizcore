# frozen_string_literal: true

module Vizcore
  module DSL
    # Resolves `map` definitions into concrete per-layer parameter values.
    class MappingResolver
      def initialize
        @mapping_state = {}
      end

      # @param scene_layers [Array<Hash>]
      # @param audio [Hash]
      # @return [Array<Hash>] normalized layer payloads with resolved params
      def resolve_layers(scene_layers:, audio:)
        normalize_scene_layers(scene_layers).map do |layer|
          resolve_layer(layer, audio)
        end
      end

      private

      def resolve_layer(layer, audio)
        params = (layer[:params] || {}).dup
        params.merge!(resolve_mappings(layer[:mappings], audio, layer_name: layer[:name]))

        output = {
          name: layer.fetch(:name).to_s,
          type: (layer[:type] || :geometry).to_s,
          params: params
        }
        output[:shader] = layer[:shader].to_s if layer[:shader]
        output[:glsl] = layer[:glsl].to_s if layer[:glsl]
        output[:glsl_source] = layer[:glsl_source].to_s if layer[:glsl_source]
        output
      end

      def resolve_mappings(mappings, audio, layer_name:)
        Array(mappings).each_with_object({}) do |mapping, resolved|
          source = mapping[:source]
          target = mapping[:target]
          next unless source && target

          value = resolve_source_value(source, audio)
          value = apply_transform(value, mapping[:transform], state_key: [layer_name, target, source])
          resolved[target.to_sym] = value unless value.nil?
        end
      end

      def resolve_source_value(source, audio)
        case source[:kind]&.to_sym
        when :amplitude
          audio[:amplitude]
        when :frequency_band
          audio.dig(:bands, source[:band]&.to_sym)
        when :fft_spectrum
          audio[:fft]
        when :beat
          audio[:beat]
        when :beat_pulse
          audio[:beat_pulse]
        when :beat_count
          audio[:beat_count]
        when :bpm
          audio[:bpm]
        else
          nil
        end
      end

      def apply_transform(value, transform, state_key:)
        return value if transform.nil? || transform.empty?
        return transform_array(value, transform) if value.is_a?(Array)
        return nil if value.is_a?(Hash) || value.nil?

        transformed = transform_scalar(value, transform)
        return nil if transformed.nil?

        apply_smoothing(transformed, transform, state_key)
      end

      def transform_array(value, transform)
        value.map do |entry|
          transform_scalar(entry, transform, fallback: 0.0) || 0.0
        end
      end

      def transform_scalar(value, transform, fallback: nil)
        numeric = numeric_value(value, fallback: fallback)
        return nil if numeric.nil?

        numeric *= Float(transform[:gain]) if transform.key?(:gain)
        numeric = apply_curve(numeric, transform[:curve]) if transform[:curve]
        numeric = [numeric, Float(transform[:min])].max if transform.key?(:min)
        numeric = [numeric, Float(transform[:max])].min if transform.key?(:max)
        numeric
      end

      def numeric_value(value, fallback:)
        return value ? 1.0 : 0.0 if value == true || value == false

        Float(value)
      rescue ArgumentError, TypeError
        fallback
      end

      def apply_curve(value, curve)
        case curve.to_sym
        when :linear
          value
        when :sqrt
          Math.sqrt([value, 0.0].max)
        when :square
          value * value
        end
      end

      def apply_smoothing(value, transform, state_key)
        return value unless transform.key?(:attack) || transform.key?(:release)

        previous = @mapping_state[state_key]
        if previous.nil?
          @mapping_state[state_key] = value
          return value
        end

        alpha = value >= previous ? transform.fetch(:attack, 1.0) : transform.fetch(:release, 1.0)
        smoothed = previous + (value - previous) * alpha
        @mapping_state[state_key] = smoothed
        smoothed
      end

      def normalize_scene_layers(scene_layers)
        Array(scene_layers).map { |layer| deep_symbolize(layer) }
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, entry), output|
            output[key.to_sym] = deep_symbolize(entry)
          end
        when Array
          value.map { |entry| deep_symbolize(entry) }
        else
          value
        end
      end
    end
  end
end
