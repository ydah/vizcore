# frozen_string_literal: true

module Vizcore
  module DSL
    # Evaluates transition rules and returns scene-change payloads.
    class TransitionController
      DEFAULT_FRAME_RATE = 60.0

      # @param scenes [Array<Hash>]
      # @param transitions [Array<Hash>]
      # @param error_reporter [#call, nil]
      def initialize(scenes:, transitions:, error_reporter: nil)
        @error_reporter = error_reporter || ->(_message) {}
        update(scenes: scenes, transitions: transitions)
      end

      # @param scenes [Array<Hash>]
      # @param transitions [Array<Hash>]
      # @return [void]
      def update(scenes:, transitions:)
        @scenes_by_name = normalize_scenes(scenes)
        @transitions = normalize_transitions(transitions)
      end

      # @param scene_name [String, Symbol]
      # @param audio [Hash]
      # @param frame_count [Integer]
      # @param elapsed_seconds [Numeric, nil]
      # @return [Hash, nil] transition payload when condition matches
      def next_transition(scene_name:, audio:, frame_count: 0, elapsed_seconds: nil)
        current = scene_name.to_sym
        transition = @transitions.find do |entry|
          entry[:from] == current && trigger_match?(entry, audio, frame_count, elapsed_seconds)
        end
        return nil unless transition

        target_scene = @scenes_by_name[transition[:to]]
        return nil unless target_scene

        {
          from: transition[:from],
          to: transition[:to],
          effect: transition[:effect],
          scene: deep_dup(target_scene)
        }
      end

      private

      def normalize_scenes(scenes)
        Array(scenes).each_with_object({}) do |scene, output|
          values = symbolize_hash(scene)
          name = values[:name]
          next unless name

          output[name.to_sym] = {
            name: name.to_sym,
            layers: Array(values[:layers]).map { |layer| deep_dup(layer) }
          }
        end
      end

      def normalize_transitions(transitions)
        Array(transitions).filter_map do |transition|
          values = symbolize_hash(transition)
          from = values[:from]
          to = values[:to]
          next unless from && to

          {
            from: from.to_sym,
            to: to.to_sym,
            trigger: values[:trigger],
            effect: deep_dup(values[:effect])
          }
        end
      end

      def trigger_match?(transition, audio, frame_count, elapsed_seconds)
        trigger = transition[:trigger]
        return false unless trigger.respond_to?(:call)

        TriggerContext.new(audio, frame_count: frame_count, elapsed_seconds: elapsed_seconds).instance_exec(&trigger)
      rescue StandardError => e
        report_trigger_error(transition, e)
        false
      end

      def report_trigger_error(transition, error)
        @error_reporter.call(
          "transition trigger failed: #{transition[:from]} -> #{transition[:to]} (#{error.class}: #{error.message})"
        )
      rescue StandardError
        nil
      end

      def symbolize_hash(value)
        Hash(value).each_with_object({}) do |(key, entry), output|
          output[key.to_sym] = entry
        end
      rescue StandardError
        {}
      end

      def deep_dup(value)
        Vizcore::DeepCopy.copy(value)
      end

      # Runtime DSL context exposed to transition trigger blocks.
      # @api private
      class TriggerContext
        # @param audio [Hash]
        # @param frame_count [Integer]
        # @param elapsed_seconds [Numeric, nil]
        def initialize(audio, frame_count:, elapsed_seconds: nil)
          @audio = symbolize_hash(audio)
          @bands = symbolize_hash(@audio[:bands])
          @band_peaks = symbolize_hash(@audio[:band_peaks])
          @onsets = symbolize_hash(@audio[:onsets])
          @drums = symbolize_hash(@audio[:drums])
          @frame_count = Integer(frame_count)
          @elapsed_seconds = normalize_elapsed_seconds(elapsed_seconds)
        rescue StandardError
          @frame_count = 0
          @elapsed_seconds = nil
        end

        # @return [Float]
        def amplitude
          @audio[:amplitude].to_f
        end

        # @return [Float]
        def peak
          @audio[:peak].to_f
        end

        # @param name [Symbol, String]
        # @return [Float]
        def frequency_band(name)
          @bands[name.to_sym].to_f
        end

        # @param name [Symbol, String]
        # @return [Float]
        def frequency_band_peak(name)
          @band_peaks[name.to_sym].to_f
        end

        # @return [Float]
        def sub
          frequency_band(:sub)
        end

        # @return [Float]
        def sub_peak
          frequency_band_peak(:sub)
        end

        # @return [Float]
        def low
          frequency_band(:low)
        end

        # @return [Float]
        def low_peak
          frequency_band_peak(:low)
        end

        # @return [Float]
        def bass
          frequency_band(:low)
        end

        # @return [Float]
        def bass_peak
          frequency_band_peak(:low)
        end

        # @return [Float]
        def mid
          frequency_band(:mid)
        end

        # @return [Float]
        def mid_peak
          frequency_band_peak(:mid)
        end

        # @return [Float]
        def high
          frequency_band(:high)
        end

        # @return [Float]
        def high_peak
          frequency_band_peak(:high)
        end

        # @return [Float]
        def treble
          frequency_band(:high)
        end

        # @return [Float]
        def treble_peak
          frequency_band_peak(:high)
        end

        # @return [Array<Float>]
        def fft_spectrum
          Array(@audio[:fft])
        end

        # @param name [Symbol, String, nil]
        # @return [Float]
        def onset(name = nil)
          return @audio[:onset].to_f if name.nil?

          @onsets[name.to_sym].to_f
        end

        # @return [Float]
        def kick
          @drums[:kick].to_f
        end

        # @return [Float]
        def snare
          @drums[:snare].to_f
        end

        # @return [Float]
        def hihat
          @drums[:hihat].to_f
        end

        # @return [Boolean]
        def beat?
          !!@audio[:beat]
        end

        # @return [Boolean]
        def beat
          beat?
        end

        # @return [Float]
        def beat_confidence
          @audio[:beat_confidence].to_f
        end

        # @return [Float]
        def beat_pulse
          @audio[:beat_pulse].to_f
        end

        # @return [Integer]
        def beat_count
          Integer(@audio[:beat_count] || 0)
        rescue StandardError
          0
        end

        # @return [Float]
        def beat_phase
          @audio[:beat_phase].to_f
        end

        # @return [Boolean]
        def beat_2
          !!@audio[:beat_2]
        end

        # @return [Boolean]
        def beat_4
          !!@audio[:beat_4]
        end

        # @return [Boolean]
        def beat_8
          !!@audio[:beat_8]
        end

        # @return [Boolean]
        def beat_triplet
          !!@audio[:beat_triplet]
        end

        # @return [Boolean]
        def triplet
          beat_triplet
        end

        # @return [Float]
        def bar_phase
          @audio[:bar_phase].to_f
        end

        # @return [Integer]
        def bar_count
          Integer(@audio[:bar_count] || 0)
        rescue StandardError
          0
        end

        # @return [Integer]
        def phrase_count
          Integer(@audio[:phrase_count] || 0)
        rescue StandardError
          0
        end

        # @return [Float]
        def bpm
          @audio[:bpm].to_f
        end

        # @return [Float]
        def bpm_confidence
          @audio[:bpm_confidence].to_f
        end

        # @return [Float]
        def spectral_centroid
          @audio[:spectral_centroid].to_f
        end

        # @return [Float]
        def spectral_rolloff
          @audio[:spectral_rolloff].to_f
        end

        # @return [Float]
        def spectral_flatness
          @audio[:spectral_flatness].to_f
        end

        # @return [Float]
        def spectral_flux
          @audio[:spectral_flux].to_f
        end

        # @return [Float]
        def zero_crossing_rate
          @audio[:zero_crossing_rate].to_f
        end

        # @return [Integer]
        def frame_count
          @frame_count
        end

        # @return [Float] scene-local elapsed seconds
        def seconds
          return @elapsed_seconds if @elapsed_seconds

          @frame_count / DEFAULT_FRAME_RATE
        end

        private

        def normalize_elapsed_seconds(value)
          return nil if value.nil?

          numeric = Float(value)
          numeric.finite? ? numeric : nil
        rescue StandardError
          nil
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
end
