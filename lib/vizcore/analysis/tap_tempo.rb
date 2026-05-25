# frozen_string_literal: true

module Vizcore
  module Analysis
    # Estimates a fixed BPM from manual tap timestamps.
    class TapTempo
      DEFAULT_MIN_BPM = 40.0
      DEFAULT_MAX_BPM = 240.0
      DEFAULT_HISTORY_SIZE = 4
      DEFAULT_RESET_AFTER_MS = 2_500.0

      def initialize(
        min_bpm: DEFAULT_MIN_BPM,
        max_bpm: DEFAULT_MAX_BPM,
        history_size: DEFAULT_HISTORY_SIZE,
        reset_after_ms: DEFAULT_RESET_AFTER_MS
      )
        @min_bpm = Float(min_bpm)
        @max_bpm = Float(max_bpm)
        @history_size = Integer(history_size).clamp(1, 16)
        @reset_after_ms = Float(reset_after_ms)
        @last_tap_ms = nil
        @intervals = []
      end

      # @param timestamp_ms [Numeric] tap timestamp in milliseconds
      # @return [Float, nil] estimated BPM after at least two taps
      def tap(timestamp_ms:)
        current = Float(timestamp_ms)
        reset_if_stale(current)
        return remember_first_tap(current) unless @last_tap_ms

        interval = current - @last_tap_ms
        @last_tap_ms = current
        return nil unless valid_interval?(interval)

        @intervals << interval
        @intervals.shift while @intervals.length > @history_size
        bpm_from_intervals
      rescue ArgumentError, TypeError
        nil
      end

      private

      def reset_if_stale(current)
        return unless @last_tap_ms
        return unless current - @last_tap_ms > @reset_after_ms

        @last_tap_ms = nil
        @intervals.clear
      end

      def remember_first_tap(current)
        @last_tap_ms = current
        nil
      end

      def valid_interval?(interval)
        return false unless interval.positive?

        bpm = 60_000.0 / interval
        bpm.between?(@min_bpm, @max_bpm)
      end

      def bpm_from_intervals
        return nil if @intervals.empty?

        interval = robust_interval(@intervals)
        (60_000.0 / interval).clamp(@min_bpm, @max_bpm)
      end

      def robust_interval(intervals)
        sorted = intervals.sort
        return median(sorted) if sorted.length < 4

        trimmed = sorted[1...-1]
        trimmed.sum / trimmed.length.to_f
      end

      def median(sorted)
        midpoint = sorted.length / 2
        return sorted[midpoint] if sorted.length.odd?

        (sorted[midpoint - 1] + sorted[midpoint]) / 2.0
      end
    end
  end
end
