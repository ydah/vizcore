# frozen_string_literal: true

module Vizcore
  module Analysis
    class Smoother
      def initialize(alpha: 0.35)
        @alpha = normalize_alpha(alpha)
        @states = {}
      end

      def smooth(key, value, alpha: @alpha)
        normalized = Float(value)
        step = normalize_alpha(alpha)
        previous = @states[key]
        current = previous.nil? ? normalized : previous + (normalized - previous) * step
        @states[key] = current
      rescue ArgumentError, TypeError
        0.0
      end

      def smooth_hash(values, namespace:, alpha: @alpha)
        Hash(values).each_with_object({}) do |(entry_key, value), result|
          result[entry_key] = smooth([namespace, entry_key], value, alpha: alpha)
        end
      end

      def smooth_array(values, namespace:, alpha: @alpha)
        Array(values).each_with_index.map do |value, index|
          smooth([namespace, index], value, alpha: alpha)
        end
      end

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
