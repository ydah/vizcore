# frozen_string_literal: true

module Vizcore
  module DSL
    class TransitionController
      def initialize(scenes:, transitions:)
        update(scenes: scenes, transitions: transitions)
      end

      def update(scenes:, transitions:)
        @scenes_by_name = normalize_scenes(scenes)
        @transitions = normalize_transitions(transitions)
      end

      def next_transition(scene_name:, audio:)
        current = scene_name.to_sym
        transition = @transitions.find do |entry|
          entry[:from] == current && trigger_match?(entry[:trigger], audio)
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

      def trigger_match?(trigger, audio)
        return false unless trigger.respond_to?(:call)

        TriggerContext.new(audio).instance_exec(&trigger)
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

      class TriggerContext
        def initialize(audio)
          @audio = symbolize_hash(audio)
          @bands = symbolize_hash(@audio[:bands])
        end

        def amplitude
          @audio[:amplitude].to_f
        end

        def frequency_band(name)
          @bands[name.to_sym].to_f
        end

        def fft_spectrum
          Array(@audio[:fft])
        end

        def beat?
          !!@audio[:beat]
        end

        def beat_count
          Integer(@audio[:beat_count] || 0)
        rescue StandardError
          0
        end

        def bpm
          @audio[:bpm].to_f
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
