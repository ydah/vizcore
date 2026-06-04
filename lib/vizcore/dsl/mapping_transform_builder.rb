# frozen_string_literal: true

module Vizcore
  module DSL
    # Collects block-style mapping transform options.
    class MappingTransformBuilder
      TRIGGER_MODES = %i[continuous trigger].freeze

      # @param initial [Hash]
      def initialize(initial = {})
        @values = initial.each_with_object({}) do |(key, value), output|
          output[key.to_sym] = value
        end
      end

      # @return [Vizcore::DSL::MappingTransformBuilder]
      def evaluate(&block)
        instance_eval(&block) if block
        self
      end

      # @param value [Numeric]
      # @return [Numeric]
      def gain(value)
        @values[:gain] = value
      end

      # @param value [Range, Array]
      # @return [Range, Array]
      def range(value)
        @values[:range] = value
      end

      # @param value [Numeric]
      # @return [Numeric]
      def min(value)
        @values[:min] = value
      end

      # @param value [Numeric]
      # @return [Numeric]
      def max(value)
        @values[:max] = value
      end

      # @param value [Symbol, String]
      # @return [Symbol, String]
      def curve(value)
        @values[:curve] = value
      end

      # @param value [Numeric]
      # @return [Numeric]
      def deadzone(value)
        @values[:deadzone] = value
      end

      # @param value [Numeric]
      # @return [Numeric]
      def threshold(value)
        @values[:threshold] = value
      end

      # @param value [Numeric]
      # @return [Numeric]
      def hysteresis(value)
        @values[:hysteresis] = value
      end

      # @param value [Numeric] hold duration in seconds at the runtime frame cadence
      # @return [Numeric]
      def hold(value)
        @values[:hold] = value
      end

      # @param value [String]
      # @return [String]
      def fallback(value)
        @values[:fallback] = value
      end

      # @param value [String]
      # @return [String]
      def prefix(value)
        @values[:prefix] = value
      end

      # @param value [String]
      # @return [String]
      def suffix(value)
        @values[:suffix] = value
      end

      # @param value [Numeric] per-frame decay multiplier
      # @return [Numeric]
      def decay(value)
        @values[:decay] = value
      end

      # @param seconds [Numeric]
      # @return [Numeric]
      def cooldown(seconds)
        @values[:cooldown] = seconds
      end

      # @param enabled [Boolean, nil]
      # @return [Boolean]
      def one_shot(enabled = true)
        @values[:one_shot] = !!enabled
      end

      # @param attack [Numeric, nil]
      # @param release [Numeric, nil]
      # @return [Hash]
      def smooth(attack: nil, release: nil)
        @values[:attack] = attack unless attack.nil?
        @values[:release] = release unless release.nil?
        @values
      end

      # @param mode [Symbol, String]
      # @return [Symbol]
      def as(mode)
        normalized = mode.to_sym
        unless TRIGGER_MODES.include?(normalized)
          raise ArgumentError, "mapping as must be :continuous or :trigger"
        end

        @values[:as] = normalized
        normalized
      end

      # @return [Hash]
      def to_h
        @values.dup
      end
    end
  end
end
