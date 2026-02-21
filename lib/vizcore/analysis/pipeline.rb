# frozen_string_literal: true

module Vizcore
  module Analysis
    class Pipeline
      attr_reader :fft_processor, :band_splitter, :beat_detector, :bpm_estimator, :smoother

      def initialize(sample_rate: 44_100, fft_size: 1024, window: :hamming, beat_detector: nil, bpm_estimator: nil, smoother: nil)
        @fft_processor = FFTProcessor.new(sample_rate: sample_rate, fft_size: fft_size, window: window)
        @band_splitter = BandSplitter.new(sample_rate: sample_rate, fft_size: fft_size)
        @beat_detector = beat_detector || BeatDetector.new
        frame_rate = sample_rate.to_f / fft_size.to_f
        @bpm_estimator = bpm_estimator || BPMEstimator.new(frame_rate: frame_rate)
        @smoother = smoother || Smoother.new(alpha: 0.35)
      end

      def call(samples)
        fft = @fft_processor.call(samples)
        bands = @band_splitter.call(fft[:magnitudes])
        beat = @beat_detector.call(samples)
        bpm = @bpm_estimator.call(beat: beat[:beat])
        amplitude = rms(samples)
        spectrum_preview = preview_spectrum(fft[:magnitudes])

        {
          amplitude: @smoother.smooth(:amplitude, amplitude),
          bands: @smoother.smooth_hash(bands, namespace: :bands),
          fft: @smoother.smooth_array(spectrum_preview, namespace: :fft),
          beat: beat[:beat],
          beat_count: beat[:beat_count],
          bpm: @smoother.smooth(:bpm, bpm, alpha: 0.2),
          peak_frequency: fft[:peak_frequency]
        }
      end

      private

      def preview_spectrum(magnitudes, bins: 32)
        values = Array(magnitudes)
        return Array.new(bins, 0.0) if values.empty?

        step = [values.length / bins, 1].max

        Array.new(bins) do |index|
          window = values[index * step, step]
          next 0.0 if window.nil? || window.empty?

          (window.sum / window.length.to_f).clamp(0.0, 1.0)
        end
      end

      def rms(samples)
        values = Array(samples).map { |sample| Float(sample) }
        return 0.0 if values.empty?

        sum = values.reduce(0.0) { |acc, sample| acc + sample * sample }
        Math.sqrt(sum / values.length.to_f).clamp(0.0, 1.0)
      rescue ArgumentError, TypeError
        0.0
      end
    end
  end
end
