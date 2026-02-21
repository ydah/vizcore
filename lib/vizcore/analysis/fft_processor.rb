# frozen_string_literal: true

module Vizcore
  module Analysis
    class FFTProcessor
      SUPPORTED_WINDOWS = %i[hamming hann blackman none].freeze

      attr_reader :sample_rate, :fft_size, :window

      def initialize(sample_rate: 44_100, fft_size: 1024, window: :hamming)
        @sample_rate = Integer(sample_rate)
        @fft_size = Integer(fft_size)
        @window = window.to_sym

        raise ArgumentError, "fft_size must be power of two" unless power_of_two?(@fft_size)
        raise ArgumentError, "unsupported window: #{@window}" unless SUPPORTED_WINDOWS.include?(@window)
      end

      def call(samples)
        frame = prepare_frame(samples)
        windowed = apply_window(frame)
        spectrum = fft(windowed.map { |value| Complex(value, 0.0) })
        half_spectrum = spectrum.first(@fft_size / 2)
        magnitudes = half_spectrum.map(&:abs)
        peak_bin = peak_index(magnitudes)

        {
          magnitudes: magnitudes,
          spectrum: half_spectrum,
          peak_bin: peak_bin,
          peak_frequency: bin_frequency(peak_bin)
        }
      end

      def bin_frequency(bin_index)
        Integer(bin_index) * sample_rate.to_f / fft_size.to_f
      end

      private

      def prepare_frame(samples)
        values = Array(samples).map { |sample| Float(sample) }
        values = values.first(fft_size)
        return values if values.length == fft_size

        values + Array.new(fft_size - values.length, 0.0)
      rescue ArgumentError, TypeError
        Array.new(fft_size, 0.0)
      end

      def apply_window(frame)
        return frame if window == :none

        frame.each_with_index.map do |value, index|
          value * window_coefficient(index, frame.length)
        end
      end

      def window_coefficient(index, size)
        angle = 2.0 * Math::PI * index.to_f / (size - 1).to_f

        case window
        when :hamming
          0.54 - 0.46 * Math.cos(angle)
        when :hann
          0.5 * (1.0 - Math.cos(angle))
        when :blackman
          0.42 - 0.5 * Math.cos(angle) + 0.08 * Math.cos(2 * angle)
        else
          1.0
        end
      end

      def fft(values)
        n = values.length
        bit_reversed = bit_reverse_copy(values)

        len = 2
        while len <= n
          angle = -2.0 * Math::PI / len
          twiddle_step = Complex(Math.cos(angle), Math.sin(angle))

          (0...n).step(len) do |offset|
            twiddle = Complex(1.0, 0.0)
            half = len / 2

            half.times do |index|
              even = bit_reversed[offset + index]
              odd = bit_reversed[offset + index + half] * twiddle
              bit_reversed[offset + index] = even + odd
              bit_reversed[offset + index + half] = even - odd
              twiddle *= twiddle_step
            end
          end

          len <<= 1
        end

        bit_reversed
      end

      def bit_reverse_copy(values)
        n = values.length
        output = values.dup
        j = 0

        (1...n).each do |i|
          bit = n >> 1
          while j & bit != 0
            j ^= bit
            bit >>= 1
          end
          j ^= bit
          output[i], output[j] = output[j], output[i] if i < j
        end

        output
      end

      def power_of_two?(value)
        value.positive? && (value & (value - 1)).zero?
      end

      def peak_index(magnitudes)
        pair = magnitudes.each_with_index.max_by { |magnitude, _index| magnitude }
        pair ? pair.last : 0
      end
    end
  end
end
