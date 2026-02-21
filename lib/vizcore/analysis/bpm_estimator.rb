# frozen_string_literal: true

module Vizcore
  module Analysis
    class BPMEstimator
      attr_reader :frame_rate

      def initialize(frame_rate:, min_bpm: 60.0, max_bpm: 200.0, history_seconds: 10.0, smoothing: 0.25, min_onsets: 4)
        @frame_rate = Float(frame_rate)
        @min_bpm = Float(min_bpm)
        @max_bpm = Float(max_bpm)
        @history_size = [(@frame_rate * Float(history_seconds)).to_i, 8].max
        @smoothing = Float(smoothing)
        @min_onsets = Integer(min_onsets)
        @history = []
        @current_bpm = 0.0
      end

      def call(beat:)
        @history << (beat ? 1.0 : 0.0)
        @history.shift while @history.length > @history_size

        return @current_bpm if onset_count < @min_onsets

        candidate = estimate_candidate_bpm
        return @current_bpm if candidate <= 0.0

        @current_bpm =
          if @current_bpm <= 0.0
            candidate
          else
            @current_bpm + (candidate - @current_bpm) * @smoothing
          end

        @current_bpm
      end

      private

      def onset_count
        @history.count { |value| value.positive? }
      end

      def estimate_candidate_bpm
        n = @history.length
        return 0.0 if n < 2

        min_lag = [(60.0 * @frame_rate / @max_bpm).round, 1].max
        max_lag = [(60.0 * @frame_rate / @min_bpm).round, n - 1].min
        return 0.0 if min_lag > max_lag

        best_lag = nil
        best_score = -Float::INFINITY

        (min_lag..max_lag).each do |lag|
          score = autocorrelation_at_lag(lag)
          next unless score > best_score

          best_score = score
          best_lag = lag
        end

        return 0.0 unless best_lag && best_score.positive?

        (60.0 * @frame_rate / best_lag).clamp(@min_bpm, @max_bpm)
      end

      def autocorrelation_at_lag(lag)
        score = 0.0
        (lag...@history.length).each do |index|
          score += @history[index] * @history[index - lag]
        end
        score
      end
    end
  end
end
