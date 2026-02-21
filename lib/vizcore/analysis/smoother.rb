# frozen_string_literal: true

module Vizcore
  module Analysis
    # Utility for smoothing scalar, hash, and array signals with EMA.
    class Smoother
      # @param alpha [Float] default smoothing coefficient (0.0..1.0)
      def initialize(alpha: 0.35)
        @alpha = normalize_alpha(alpha)
        @states = {}
      end

      # Smooth one scalar value under a key.
      #
      # @param key [Object] state key
      # @param value [Numeric]
      # @param alpha [Float]
      # @return [Float]
      def smooth(key, value, alpha: @alpha)
        normalized = Float(value)
        step = normalize_alpha(alpha)
        previous = @states[key]
        current = previous.nil? ? normalized : previous + (normalized - previous) * step
        @states[key] = current
      rescue ArgumentError, TypeError
        0.0
      end

      # Smooth each value in a hash independently.
      #
      # @param values [Hash]
      # @param namespace [Object]
      # @param alpha [Float]
      # @return [Hash]
      def smooth_hash(values, namespace:, alpha: @alpha)
        Hash(values).each_with_object({}) do |(entry_key, value), result|
          result[entry_key] = smooth([namespace, entry_key], value, alpha: alpha)
        end
      end

      # Smooth each value in an array independently.
      #
      # @param values [Array]
      # @param namespace [Object]
      # @param alpha [Float]
      # @return [Array<Float>]
      def smooth_array(values, namespace:, alpha: @alpha)
        Array(values).each_with_index.map do |value, index|
          smooth([namespace, index], value, alpha: alpha)
        end
      end

      # Reset smoothing state.
      #
      # @param namespace [Object, nil] when provided, resets keys under this namespace only
      # @return [void]
      def reset(namespace = nil)
        return @states.clear if namespace.nil?

        @states.delete_if do |key, _value|
          key.is_a?(Array) && key.first == namespace
        end
      end

      private

      def normalize_alpha(value)
        Float(value).clamp(0.0, 1.0)
      rescue ArgumentError, TypeError
        0.35
      end
    end
  end
end
