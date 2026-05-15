# frozen_string_literal: true

module Vizcore
  module Analysis
    # Scales audio features against a rolling amplitude peak for repeatable mappings.
    class AdaptiveNormalizer
      DEFAULT_WINDOW_SIZE = 128
      DEFAULT_TARGET = 0.85
      DEFAULT_FLOOR = 0.05

      # @param window_size [Integer] number of recent active frames used to track the peak
      # @param target [Numeric] desired level for the rolling peak
      # @param floor [Numeric] minimum peak level used when calculating gain
      def initialize(window_size: DEFAULT_WINDOW_SIZE, target: DEFAULT_TARGET, floor: DEFAULT_FLOOR)
        @window_size = normalize_window_size(window_size)
        @target = normalize_unit(target, DEFAULT_TARGET)
        @floor = normalize_unit(floor, DEFAULT_FLOOR)
        @history = []
      end

      # @param amplitude [Numeric] current RMS amplitude
      # @param bands [Hash] current frequency band values
      # @param fft [Array<Numeric>] current FFT preview values
      # @return [Hash] normalized feature values plus the applied gain
      def call(amplitude:, bands:, fft:)
        current_amplitude = normalize_unit(amplitude, 0.0)
        @history << current_amplitude
        @history.shift while @history.length > @window_size

        gain = @target / [@history.max.to_f, @floor].max
        {
          amplitude: scale_value(current_amplitude, gain),
          bands: scale_hash(bands, gain),
          fft: scale_array(fft, gain),
          gain: gain
        }
      end

      private

      def normalize_window_size(value)
        Integer(value).clamp(1, 10_000)
      rescue ArgumentError, TypeError
        DEFAULT_WINDOW_SIZE
      end

      def normalize_unit(value, fallback)
        Float(value).clamp(0.0, 1.0)
      rescue ArgumentError, TypeError
        fallback
      end

      def scale_hash(values, gain)
        Hash(values).transform_values { |value| scale_value(value, gain) }
      rescue StandardError
        {}
      end

      def scale_array(values, gain)
        Array(values).map { |value| scale_value(value, gain) }
      end

      def scale_value(value, gain)
        (Float(value) * gain).clamp(0.0, 1.0)
      rescue ArgumentError, TypeError
        0.0
      end
    end
  end
end
