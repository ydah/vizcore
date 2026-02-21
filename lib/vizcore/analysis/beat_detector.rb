# frozen_string_literal: true

module Vizcore
  module Analysis
    # Detects beat onsets using short-term energy thresholding.
    class BeatDetector
      attr_reader :beat_count

      # @param history_size [Integer] number of historical frames to keep
      # @param sensitivity [Float] multiplier applied to moving average energy
      # @param refractory_frames [Integer] minimum frames between beat events
      # @param min_history [Integer] minimum history size before detecting beats
      def initialize(history_size: 43, sensitivity: 1.35, refractory_frames: 4, min_history: 8)
        @history_size = Integer(history_size)
        @sensitivity = Float(sensitivity)
        @refractory_frames = Integer(refractory_frames)
        @min_history = Integer(min_history)
        @energy_history = []
        @frame_index = 0
        @last_beat_frame = -@refractory_frames
        @beat_count = 0
      end

      # @param samples [Array<Numeric>] PCM frame samples
      # @return [Hash] beat flag and detector internals
      def call(samples)
        instant_energy = frame_energy(samples)
        average_energy = average(@energy_history)
        threshold = average_energy * @sensitivity
        enough_history = @energy_history.length >= @min_history
        refractory_ok = (@frame_index - @last_beat_frame) > @refractory_frames
        beat = enough_history && refractory_ok && instant_energy > threshold && instant_energy.positive?

        if beat
          @beat_count += 1
          @last_beat_frame = @frame_index
        end

        @energy_history << instant_energy
        @energy_history.shift while @energy_history.length > @history_size
        @frame_index += 1

        {
          beat: beat,
          beat_count: @beat_count,
          instant_energy: instant_energy,
          average_energy: average_energy,
          threshold: threshold
        }
      end

      private

      def frame_energy(samples)
        values = Array(samples).map { |sample| Float(sample) }
        return 0.0 if values.empty?

        values.reduce(0.0) { |sum, value| sum + value * value } / values.length.to_f
      rescue ArgumentError, TypeError
        0.0
      end

      def average(values)
        return 0.0 if values.empty?

        values.sum / values.length.to_f
      end
    end
  end
end
