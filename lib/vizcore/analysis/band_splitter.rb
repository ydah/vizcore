# frozen_string_literal: true

module Vizcore
  module Analysis
    # Converts FFT magnitudes into normalized sub/low/mid/high band energies.
    class BandSplitter
      # Frequency ranges for each named band in Hz.
      BANDS = {
        sub: [20.0, 60.0],
        low: [60.0, 250.0],
        mid: [250.0, 4000.0],
        high: [4000.0, 20_000.0]
      }.freeze

      attr_reader :sample_rate, :fft_size

      # @param sample_rate [Integer] input sample rate
      # @param fft_size [Integer] FFT frame size used to compute magnitudes
      def initialize(sample_rate: 44_100, fft_size: 1024)
        @sample_rate = Integer(sample_rate)
        @fft_size = Integer(fft_size)
        @bin_hz = @sample_rate.to_f / @fft_size.to_f
      end

      # @param magnitudes [Array<Numeric>] FFT magnitude bins
      # @return [Hash] normalized energy values for `:sub/:low/:mid/:high`
      def call(magnitudes)
        values = normalize_magnitudes(magnitudes)
        return BANDS.transform_values { 0.0 } if values.empty?

        scale = [values.max, 1.0e-9].max

        BANDS.transform_values do |(low_hz, high_hz)|
          indices = band_indices(low_hz, high_hz, values.length)
          next 0.0 if indices.empty?

          average = indices.sum { |index| values[index] } / indices.length.to_f
          (average / scale).clamp(0.0, 1.0)
        end
      end

      private

      def normalize_magnitudes(magnitudes)
        Array(magnitudes).map { |value| Float(value).abs }
      rescue ArgumentError, TypeError
        []
      end

      def band_indices(low_hz, high_hz, length)
        return [] if length.zero?

        first = (low_hz / @bin_hz).floor
        last = (high_hz / @bin_hz).ceil
        first = first.clamp(0, length - 1)
        last = last.clamp(0, length - 1)
        return [] if first > last

        (first..last).to_a
      end
    end
  end
end
