# frozen_string_literal: true

module Vizcore
  module DSL
    # Evaluates transition rules and returns scene-change payloads.
    class TransitionController
      # @param scenes [Array<Hash>]
      # @param transitions [Array<Hash>]
      def initialize(scenes:, transitions:)
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
      # @return [Hash, nil] transition payload when condition matches
      def next_transition(scene_name:, audio:, frame_count: 0)
        current = scene_name.to_sym
        transition = @transitions.find do |entry|
          entry[:from] == current && trigger_match?(entry[:trigger], audio, frame_count)
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

      def trigger_match?(trigger, audio, frame_count)
        return false unless trigger.respond_to?(:call)

        TriggerContext.new(audio, frame_count: frame_count).instance_exec(&trigger)
      rescue StandardError
        false
      end

      def symbolize_hash(value)
        Hash(value).each_with_object({}) do |(key, entry), output|
          output[key.to_sym] = entry
        end
      rescue StandardError
        {}
      end

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, entry), output|
            output[key] = deep_dup(entry)
          end
        when Array
          value.map { |entry| deep_dup(entry) }
        else
          value
        end
      end

      # Runtime DSL context exposed to transition trigger blocks.
      # @api private
      class TriggerContext
        # @param audio [Hash]
        # @param frame_count [Integer]
        def initialize(audio, frame_count:)
          @audio = symbolize_hash(audio)
          @bands = symbolize_hash(@audio[:bands])
          @frame_count = Integer(frame_count)
        rescue StandardError
          @frame_count = 0
        end

        # @return [Float]
        def amplitude
          @audio[:amplitude].to_f
        end

        # @param name [Symbol, String]
        # @return [Float]
        def frequency_band(name)
          @bands[name.to_sym].to_f
        end

        # @return [Array<Float>]
        def fft_spectrum
          Array(@audio[:fft])
        end

        # @return [Boolean]
        def beat?
          !!@audio[:beat]
        end

        # @return [Integer]
        def beat_count
          Integer(@audio[:beat_count] || 0)
        rescue StandardError
          0
        end

        # @return [Float]
        def bpm
          @audio[:bpm].to_f
        end

        # @return [Integer]
        def frame_count
          @frame_count
        end

        private

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
