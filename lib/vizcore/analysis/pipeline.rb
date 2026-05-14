# frozen_string_literal: true

module Vizcore
  module Analysis
    # End-to-end analysis pipeline from PCM samples to renderer-ready features.
    class Pipeline
      BEAT_PULSE_DECAY = 0.86
      BEAT_PULSE_FLOOR = 0.001
      DEFAULT_NOISE_GATE = 0.01
      SILENCE_RESET_FRAMES = 90

      attr_reader :fft_processor, :band_splitter, :beat_detector, :bpm_estimator, :smoother

      # @param sample_rate [Integer]
      # @param fft_size [Integer]
      # @param window [Symbol]
      # @param beat_detector [Vizcore::Analysis::BeatDetector, nil]
      # @param bpm_estimator [Vizcore::Analysis::BPMEstimator, nil]
      # @param smoother [Vizcore::Analysis::Smoother, nil]
      # @param noise_gate [Numeric] RMS threshold below which input is treated as silence
      def initialize(sample_rate: 44_100, fft_size: 1024, window: :hamming, beat_detector: nil, bpm_estimator: nil, smoother: nil, noise_gate: DEFAULT_NOISE_GATE)
        @fft_processor = FFTProcessor.new(sample_rate: sample_rate, fft_size: fft_size, window: window)
        @band_splitter = BandSplitter.new(sample_rate: sample_rate, fft_size: fft_size)
        @beat_detector = beat_detector || BeatDetector.new
        frame_rate = sample_rate.to_f / fft_size.to_f
        @bpm_estimator = bpm_estimator || BPMEstimator.new(frame_rate: frame_rate)
        @smoother = smoother || Smoother.new(alpha: 0.35)
        @noise_gate = normalize_noise_gate(noise_gate)
        @beat_pulse = 0.0
        @last_bpm = 0.0
        @silent_frame_count = 0
      end

      # @param samples [Array<Numeric>] audio frame samples
      # @return [Hash] normalized analysis payload consumed by frame broadcaster
      def call(samples)
        amplitude = rms(samples)
        if silence?(amplitude)
          track_silent_frame(samples)
          return silent_frame(reset_tempo: sustained_silence?)
        end

        @silent_frame_count = 0

        fft = @fft_processor.call(samples)
        bands = @band_splitter.call(fft[:magnitudes])
        beat = @beat_detector.call(samples)
        beat_detected = beat[:beat]
        @beat_pulse = beat_detected ? 1.0 : @beat_pulse * BEAT_PULSE_DECAY
        @beat_pulse = 0.0 if @beat_pulse < BEAT_PULSE_FLOOR
        bpm = resolve_bpm(beat_detected)
        spectrum_preview = preview_spectrum(fft[:magnitudes])

        {
          amplitude: @smoother.smooth(:amplitude, amplitude),
          bands: @smoother.smooth_hash(bands, namespace: :bands),
          fft: @smoother.smooth_array(spectrum_preview, namespace: :fft),
          beat: beat_detected,
          beat_pulse: @beat_pulse,
          beat_count: beat[:beat_count],
          bpm: bpm,
          peak_frequency: fft[:peak_frequency]
        }
      end

      private

      def silence?(amplitude)
        amplitude < @noise_gate
      end

      def normalize_noise_gate(value)
        Float(value).clamp(0.0, 1.0)
      rescue ArgumentError, TypeError
        DEFAULT_NOISE_GATE
      end

      def silent_frame(reset_tempo:)
        @beat_pulse = 0.0
        reset_tempo_state if reset_tempo
        @smoother.reset if @smoother.respond_to?(:reset)

        {
          amplitude: 0.0,
          bands: { sub: 0.0, low: 0.0, mid: 0.0, high: 0.0 },
          fft: Array.new(32, 0.0),
          beat: false,
          beat_pulse: 0.0,
          beat_count: current_beat_count,
          bpm: @last_bpm,
          peak_frequency: 0.0
        }
      end

      def reset_tempo_state
        @last_bpm = 0.0
        @bpm_estimator.reset if @bpm_estimator.respond_to?(:reset)
      end

      def track_silent_frame(samples)
        @silent_frame_count += 1
        @beat_detector.call(samples) if @beat_detector.respond_to?(:call)
        @last_bpm = @bpm_estimator.call(beat: false).to_f if @bpm_estimator.respond_to?(:call)
      rescue StandardError
        nil
      end

      def sustained_silence?
        @silent_frame_count == SILENCE_RESET_FRAMES
      end

      def current_beat_count
        return Integer(@beat_detector.beat_count) if @beat_detector.respond_to?(:beat_count)

        0
      rescue StandardError
        0
      end

      def resolve_bpm(beat_detected)
        bpm = @bpm_estimator.call(beat: beat_detected)
        @last_bpm = @smoother.smooth(:bpm, bpm, alpha: 0.2).to_f
      end

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
