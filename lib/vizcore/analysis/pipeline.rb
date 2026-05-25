# frozen_string_literal: true

module Vizcore
  module Analysis
    # End-to-end analysis pipeline from PCM samples to renderer-ready features.
    class Pipeline
      BEAT_PULSE_DECAY = 0.86
      BEAT_PULSE_FLOOR = 0.001
      DEFAULT_NOISE_GATE = 0.01
      DEFAULT_AUDIO_NORMALIZE = { mode: :off }.freeze
      SILENCE_RESET_FRAMES = 90

      attr_reader :fft_processor, :band_splitter, :beat_detector, :bpm_estimator, :smoother

      # @param sample_rate [Integer]
      # @param fft_size [Integer]
      # @param window [Symbol]
      # @param beat_detector [Vizcore::Analysis::BeatDetector, nil]
      # @param bpm_estimator [Vizcore::Analysis::BPMEstimator, nil]
      # @param smoother [Vizcore::Analysis::Smoother, nil]
      # @param noise_gate [Numeric] RMS threshold below which input is treated as silence
      # @param audio_normalize [Hash, nil] optional audio normalization settings
      # @param bpm [Numeric, nil] fixed BPM value used when bpm_lock is true
      # @param bpm_lock [Boolean] true when BPM output should stay fixed
      def initialize(sample_rate: 44_100, fft_size: 1024, window: :hamming, beat_detector: nil, bpm_estimator: nil, smoother: nil, noise_gate: DEFAULT_NOISE_GATE, audio_normalize: nil, bpm: nil, bpm_lock: false)
        @fft_processor = FFTProcessor.new(sample_rate: sample_rate, fft_size: fft_size, window: window)
        @band_splitter = BandSplitter.new(sample_rate: sample_rate, fft_size: fft_size)
        @beat_detector = beat_detector || BeatDetector.new
        @analysis_frame_rate = sample_rate.to_f / fft_size.to_f
        @bpm_estimator = bpm_estimator || BPMEstimator.new(frame_rate: @analysis_frame_rate)
        @smoother = smoother || Smoother.new(alpha: 0.35)
        @noise_gate = normalize_noise_gate(noise_gate)
        self.bpm_lock = { bpm: bpm, locked: bpm_lock }
        self.audio_normalize = audio_normalize
        @beat_pulse = 0.0
        @last_bpm = 0.0
        @silent_frame_count = 0
        @previous_onset_amplitude = 0.0
        @previous_onset_bands = {}
        @previous_flux_spectrum = nil
      end

      # @param settings [Hash, nil]
      # @return [Hash] normalized settings
      def audio_normalize=(settings)
        @audio_normalize = normalize_audio_normalize(settings)
        @normalizer = build_normalizer(@audio_normalize)
      end

      # @param settings [Hash]
      # @return [Float, nil]
      def bpm_lock=(settings)
        values = symbolize_hash(settings)
        @locked_bpm = normalize_locked_bpm(values[:bpm], bpm_lock: values[:locked])
        @last_bpm = @locked_bpm if @locked_bpm
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
        confidence = beat_confidence(beat)
        @beat_pulse = beat_detected ? 1.0 : @beat_pulse * BEAT_PULSE_DECAY
        @beat_pulse = 0.0 if @beat_pulse < BEAT_PULSE_FLOOR
        bpm = resolve_bpm(beat_detected)
        peak = peak_level(samples)
        spectrum_preview = preview_spectrum(fft[:magnitudes])
        spectral = spectral_features(fft[:magnitudes], spectrum_preview)
        normalized = normalize_features(
          amplitude: amplitude,
          bands: bands,
          fft: spectrum_preview
        )
        onsets = detect_onsets(amplitude: normalized[:amplitude], bands: normalized[:bands])
        drums = detect_drum_sources(bands: normalized[:bands], onsets: onsets[:bands])

        {
          amplitude: @smoother.smooth(:amplitude, normalized[:amplitude]),
          peak: peak,
          bands: @smoother.smooth_hash(normalized[:bands], namespace: :bands),
          fft: @smoother.smooth_array(normalized[:fft], namespace: :fft),
          onset: onsets[:amplitude],
          onsets: onsets[:bands],
          drums: drums,
          beat: beat_detected,
          beat_confidence: confidence,
          beat_pulse: @beat_pulse,
          beat_count: beat[:beat_count],
          bpm: bpm,
          bpm_confidence: bpm_confidence,
          spectral_centroid: spectral[:centroid],
          spectral_rolloff: spectral[:rolloff],
          spectral_flatness: spectral[:flatness],
          spectral_flux: spectral[:flux],
          zero_crossing_rate: zero_crossing_rate(samples),
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

      def normalize_audio_normalize(value)
        settings = DEFAULT_AUDIO_NORMALIZE.merge(symbolize_hash(value))
        mode = settings[:mode].to_s.strip.to_sym
        raise ArgumentError, "unsupported audio_normalize mode: #{settings[:mode]}" unless %i[off adaptive].include?(mode)

        settings.merge(mode: mode)
      end

      def normalize_locked_bpm(value, bpm_lock:)
        return nil unless bpm_lock

        numeric = Float(value)
        raise ArgumentError, "bpm must be positive when bpm_lock is enabled" unless numeric.positive?

        numeric
      rescue ArgumentError, TypeError
        raise ArgumentError, "bpm must be a positive number when bpm_lock is enabled"
      end

      def build_normalizer(settings)
        return nil unless settings[:mode] == :adaptive

        AdaptiveNormalizer.new(
          window_size: normalization_window_size(settings),
          target: settings.fetch(:target, AdaptiveNormalizer::DEFAULT_TARGET),
          floor: settings.fetch(:floor, AdaptiveNormalizer::DEFAULT_FLOOR)
        )
      end

      def normalization_window_size(settings)
        return settings[:window_size] if settings.key?(:window_size)

        seconds = settings.fetch(:window, nil)
        return AdaptiveNormalizer::DEFAULT_WINDOW_SIZE if seconds.nil?

        (Float(seconds) * @analysis_frame_rate).round.clamp(1, 10_000)
      rescue ArgumentError, TypeError
        AdaptiveNormalizer::DEFAULT_WINDOW_SIZE
      end

      def normalize_features(amplitude:, bands:, fft:)
        return { amplitude: amplitude, bands: bands, fft: fft } unless @normalizer

        @normalizer.call(amplitude: amplitude, bands: bands, fft: fft)
      end

      def detect_onsets(amplitude:, bands:)
        current_amplitude = Float(amplitude).clamp(0.0, 1.0)
        current_bands = Hash(bands).transform_values { |value| Float(value).clamp(0.0, 1.0) }

        amplitude_onset = positive_delta(current_amplitude, @previous_onset_amplitude)
        band_onsets = current_bands.each_with_object({}) do |(key, value), output|
          output[key] = positive_delta(value, @previous_onset_bands[key].to_f)
        end

        @previous_onset_amplitude = current_amplitude
        @previous_onset_bands = current_bands

        { amplitude: amplitude_onset, bands: band_onsets }
      rescue ArgumentError, TypeError
        { amplitude: 0.0, bands: {} }
      end

      def positive_delta(current, previous)
        [current - previous, 0.0].max.clamp(0.0, 1.0)
      end

      def detect_drum_sources(bands:, onsets:)
        band_values = Hash(bands)
        onset_values = Hash(onsets)

        {
          kick: drum_confidence([:sub, :low], band_values, onset_values),
          snare: drum_confidence([:mid], band_values, onset_values),
          hihat: drum_confidence([:high], band_values, onset_values)
        }
      end

      def drum_confidence(keys, bands, onsets)
        level = keys.map { |key| Float(bands[key] || 0.0) }.max || 0.0
        rise = keys.map { |key| Float(onsets[key] || 0.0) }.max || 0.0
        (level * rise).clamp(0.0, 1.0)
      rescue ArgumentError, TypeError
        0.0
      end

      def silent_frame(reset_tempo:)
        @beat_pulse = 0.0
        reset_tempo_state if reset_tempo
        @smoother.reset if @smoother.respond_to?(:reset)
        @previous_onset_amplitude = 0.0
        @previous_onset_bands = {}
        @previous_flux_spectrum = nil

        {
          amplitude: 0.0,
          peak: 0.0,
          bands: { sub: 0.0, low: 0.0, mid: 0.0, high: 0.0 },
          fft: Array.new(32, 0.0),
          onset: 0.0,
          onsets: { sub: 0.0, low: 0.0, mid: 0.0, high: 0.0 },
          drums: { kick: 0.0, snare: 0.0, hihat: 0.0 },
          beat: false,
          beat_confidence: 0.0,
          beat_pulse: 0.0,
          beat_count: current_beat_count,
          bpm: @last_bpm,
          bpm_confidence: bpm_confidence,
          spectral_centroid: 0.0,
          spectral_rolloff: 0.0,
          spectral_flatness: 0.0,
          spectral_flux: 0.0,
          zero_crossing_rate: 0.0,
          peak_frequency: 0.0
        }
      end

      def reset_tempo_state
        @last_bpm = @locked_bpm || 0.0
        @previous_flux_spectrum = nil
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

      def beat_confidence(beat)
        threshold = Float(beat[:threshold])
        instant_energy = Float(beat[:instant_energy])
        return beat[:beat] ? 1.0 : 0.0 unless threshold.positive?

        (instant_energy / threshold).clamp(0.0, 1.0)
      rescue ArgumentError, TypeError
        beat[:beat] ? 1.0 : 0.0
      end

      def resolve_bpm(beat_detected)
        return @last_bpm = @locked_bpm if @locked_bpm

        bpm = @bpm_estimator.call(beat: beat_detected)
        @last_bpm = @smoother.smooth(:bpm, bpm, alpha: 0.2).to_f
      end

      def bpm_confidence
        return 1.0 if @locked_bpm
        return @bpm_estimator.confidence.to_f if @bpm_estimator.respond_to?(:confidence)

        @last_bpm.to_f.positive? ? 1.0 : 0.0
      rescue StandardError
        0.0
      end

      def spectral_features(magnitudes, spectrum_preview)
        values = Array(magnitudes).map { |value| Float(value).abs }
        return zero_spectral_features if values.empty?

        total = values.sum
        return zero_spectral_features unless total.positive?

        {
          centroid: spectral_centroid(values, total),
          rolloff: spectral_rolloff(values, total),
          flatness: spectral_flatness(values),
          flux: spectral_flux(spectrum_preview)
        }
      rescue StandardError
        zero_spectral_features
      end

      def zero_spectral_features
        { centroid: 0.0, rolloff: 0.0, flatness: 0.0, flux: 0.0 }
      end

      def spectral_centroid(values, total)
        weighted = values.each_with_index.sum do |magnitude, index|
          @fft_processor.bin_frequency(index) * magnitude
        end
        weighted / total
      end

      def spectral_rolloff(values, total, threshold: 0.85)
        target = total * threshold
        running = 0.0
        index = values.index do |magnitude|
          running += magnitude
          running >= target
        end
        @fft_processor.bin_frequency(index || 0)
      end

      def spectral_flatness(values)
        epsilon = 1e-12
        arithmetic_mean = values.sum / values.length.to_f
        return 0.0 unless arithmetic_mean.positive?

        log_mean = values.sum { |value| Math.log([value, epsilon].max) } / values.length.to_f
        (Math.exp(log_mean) / arithmetic_mean).clamp(0.0, 1.0)
      end

      def spectral_flux(spectrum_preview)
        current = Array(spectrum_preview).map { |value| Float(value).clamp(0.0, 1.0) }
        previous = @previous_flux_spectrum
        @previous_flux_spectrum = current
        return 0.0 unless previous && previous.length == current.length

        Math.sqrt(current.each_with_index.sum { |value, index| [value - previous[index], 0.0].max**2 }).clamp(0.0, 1.0)
      rescue StandardError
        0.0
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

      def peak_level(samples)
        Array(samples).map { |sample| Float(sample).abs }.max.to_f.clamp(0.0, 1.0)
      rescue StandardError
        0.0
      end

      def zero_crossing_rate(samples)
        values = Array(samples).map { |sample| Float(sample) }
        return 0.0 if values.length < 2

        crossings = values.each_cons(2).count do |previous, current|
          (previous.negative? && current >= 0.0) || (previous.positive? && current <= 0.0)
        end
        (crossings / (values.length - 1).to_f).clamp(0.0, 1.0)
      rescue StandardError
        0.0
      end

      def symbolize_hash(value)
        Hash(value).each_with_object({}) do |(key, entry), output|
          output[key.to_sym] = entry
        end
      rescue StandardError
        {}
      end
    end
  end
end
