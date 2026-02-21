# frozen_string_literal: true

module Vizcore
  module DSL
    # Resolves `map` definitions into concrete per-layer parameter values.
    class MappingResolver
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
        params.merge!(resolve_mappings(layer[:mappings], audio))

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

      def resolve_mappings(mappings, audio)
        Array(mappings).each_with_object({}) do |mapping, resolved|
          source = mapping[:source]
          target = mapping[:target]
          next unless source && target

          value = resolve_source_value(source, audio)
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
        when :beat_count
          audio[:beat_count]
        when :bpm
          audio[:bpm]
        else
          nil
        end
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
