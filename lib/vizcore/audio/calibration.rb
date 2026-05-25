# frozen_string_literal: true

require_relative "input_manager"

module Vizcore
  module Audio
    # Samples an audio input and derives practical level/noise-gate metrics.
    class Calibration
      DEFAULT_DURATION = 3.0
      DEFAULT_FPS = 20.0

      Result = Struct.new(
        :source,
        :sample_rate,
        :frame_size,
        :frames,
        :rms_mean,
        :rms_p95,
        :peak_max,
        :clip_ratio,
        :recommended_noise_gate,
        keyword_init: true
      ) do
        def to_h
          {
            source: source,
            sample_rate: sample_rate,
            frame_size: frame_size,
            frames: frames,
            rms_mean: rms_mean,
            rms_p95: rms_p95,
            peak_max: peak_max,
            clip_ratio: clip_ratio,
            recommended_noise_gate: recommended_noise_gate
          }
        end
      end

      # @param source [String, Symbol]
      # @param file_path [String, nil]
      # @param audio_device [String, nil]
      # @param duration [Numeric]
      # @param fps [Numeric]
      # @param input_manager_factory [#call]
      # @param sleeper [#call]
      def initialize(
        source: :mic,
        file_path: nil,
        audio_device: nil,
        duration: DEFAULT_DURATION,
        fps: DEFAULT_FPS,
        input_manager_factory: nil,
        sleeper: ->(seconds) { sleep(seconds) }
      )
        @source = source.to_sym
        @file_path = file_path
        @audio_device = audio_device
        @duration = positive_float(duration, "duration")
        @fps = positive_float(fps, "fps")
        @input_manager_factory = input_manager_factory || method(:build_input_manager)
        @sleeper = sleeper
      end

      # @return [Result]
      def call
        manager = @input_manager_factory.call(source: @source, file_path: @file_path, audio_device: @audio_device)
        rms_values = []
        peak_values = []
        manager.start
        frame_count.times do
          samples = manager.capture_frame(manager.realtime_capture_size(@fps))
          rms_values << rms(samples)
          peak_values << peak(samples)
          @sleeper.call(1.0 / @fps) if @source == :mic
        end

        build_result(manager, rms_values, peak_values)
      ensure
        manager&.stop
      end

      private

      def build_input_manager(source:, file_path:, audio_device:)
        Vizcore::Audio::InputManager.new(source: source, file_path: file_path, audio_device: audio_device)
      end

      def build_result(manager, rms_values, peak_values)
        peak_max = peak_values.max.to_f
        Result.new(
          source: manager.source_name.to_s,
          sample_rate: manager.sample_rate,
          frame_size: manager.frame_size,
          frames: rms_values.length,
          rms_mean: round_metric(mean(rms_values)),
          rms_p95: round_metric(percentile(rms_values, 0.95)),
          peak_max: round_metric(peak_max),
          clip_ratio: round_metric(clip_ratio(peak_values)),
          recommended_noise_gate: round_metric(recommended_noise_gate(rms_values))
        )
      end

      def frame_count
        [(@duration * @fps).ceil, 1].max
      end

      def rms(samples)
        values = Array(samples)
        return 0.0 if values.empty?

        Math.sqrt(values.sum { |sample| sample.to_f * sample.to_f } / values.length.to_f)
      end

      def peak(samples)
        Array(samples).map { |sample| sample.to_f.abs }.max.to_f
      end

      def mean(values)
        return 0.0 if values.empty?

        values.sum / values.length.to_f
      end

      def percentile(values, ratio)
        sorted = values.sort
        return 0.0 if sorted.empty?

        sorted[((sorted.length - 1) * ratio).round]
      end

      def clip_ratio(peaks)
        return 0.0 if peaks.empty?

        peaks.count { |value| value >= 0.98 } / peaks.length.to_f
      end

      def recommended_noise_gate(rms_values)
        baseline = percentile(rms_values, 0.50)
        [[baseline * 1.5, 0.001].max, 0.25].min
      end

      def round_metric(value)
        value.to_f.round(6)
      end

      def positive_float(value, label)
        numeric = Float(value)
        raise ArgumentError, "#{label} must be positive" unless numeric.positive?

        numeric
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{label} must be positive"
      end
    end
  end
end
