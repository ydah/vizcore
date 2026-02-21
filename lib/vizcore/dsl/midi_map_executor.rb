# frozen_string_literal: true

module Vizcore
  module DSL
    class MidiMapExecutor
      def initialize(midi_maps:, scenes:, globals: {})
        update(midi_maps: midi_maps, scenes: scenes, globals: globals)
      end

      def update(midi_maps:, scenes:, globals: nil)
        @midi_maps = normalize_midi_maps(midi_maps)
        @scenes = normalize_scenes(scenes)
        @globals = normalize_globals(globals) unless globals.nil?
      end

      def globals
        @globals.dup
      end

      def handle_event(event)
        @midi_maps.each_with_object([]) do |mapping, actions|
          next unless mapping_match?(mapping[:trigger], event)

          context = ActionContext.new(scenes: @scenes, globals: @globals)
          invoke_action_block(context, mapping[:action], event, mapping[:trigger])
          actions.concat(context.actions)
        end
      end

      private

      def normalize_midi_maps(midi_maps)
        Array(midi_maps).filter_map do |mapping|
          values = symbolize_hash(mapping)
          trigger = symbolize_hash(values[:trigger])
          action = values[:action]
          next if trigger.empty?
          next unless action.respond_to?(:call)

          {
            trigger: trigger,
            action: action
          }
        end
      end

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

      def normalize_globals(globals)
        symbolize_hash(globals)
      end

      def mapping_match?(trigger, event)
        if trigger.key?(:note)
          event.type == :note_on && event.data1 == trigger[:note].to_i
        elsif trigger.key?(:cc)
          event.type == :control_change && event.data1 == trigger[:cc].to_i
        elsif trigger.key?(:pc)
          event.type == :program_change && event.data1 == trigger[:pc].to_i
        else
          false
        end
      end

      def invoke_action_block(context, action, event, trigger)
        value = event_value(event, trigger)
        if action.arity.zero?
          context.instance_exec(&action)
        else
          context.instance_exec(value, &action)
        end
      end

      def event_value(event, trigger)
        if trigger.key?(:note) || trigger.key?(:cc)
          event.data2.to_i.clamp(0, 127)
        elsif trigger.key?(:pc)
          event.data1.to_i.clamp(0, 127)
        else
          0
        end
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

      class ActionContext
        attr_reader :actions

        def initialize(scenes:, globals:)
          @scenes = scenes
          @globals = globals
          @actions = []
        end

        def switch_scene(name, effect: nil)
          scene = @scenes[name.to_sym]
          return unless scene

          @actions << {
            type: :switch_scene,
            scene: {
              name: scene[:name],
              layers: scene[:layers].map { |layer| deep_dup(layer) }
            },
            effect: deep_dup(effect)
          }
        end

        def set(key, value)
          symbol_key = key.to_sym
          @globals[symbol_key] = value
          @actions << {
            type: :set_global,
            key: symbol_key,
            value: value
          }
        end

        private

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
      end
    end
  end
end
