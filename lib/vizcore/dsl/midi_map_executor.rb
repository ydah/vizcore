# frozen_string_literal: true

module Vizcore
  module DSL
    # Executes `midi_map` action blocks against incoming MIDI events.
    class MidiMapExecutor
      # @param midi_maps [Array<Hash>]
      # @param scenes [Array<Hash>]
      # @param globals [Hash]
      def initialize(midi_maps:, scenes:, globals: {})
        update(midi_maps: midi_maps, scenes: scenes, globals: globals)
      end

      # @param midi_maps [Array<Hash>]
      # @param scenes [Array<Hash>]
      # @param globals [Hash, nil]
      # @return [void]
      def update(midi_maps:, scenes:, globals: nil)
        @midi_maps = normalize_midi_maps(midi_maps)
        @scenes = normalize_scenes(scenes)
        @globals = normalize_globals(globals) unless globals.nil?
        @cc_state = {}
      end

      # @return [Hash] mutable global parameter snapshot
      def globals
        @globals.dup
      end

      # @param event [Vizcore::Audio::MidiInput::Event]
      # @return [Array<Hash>] runtime actions (`:switch_scene`, `:set_global`)
      def handle_event(event)
        @midi_maps.each_with_object([]) do |mapping, actions|
          next unless mapping_match?(mapping[:trigger], event)

          value = event_value(event, mapping[:trigger])
          next if value.nil?

          context = ActionContext.new(scenes: @scenes, globals: @globals)
          invoke_action_block(context, mapping[:action], value)
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
        return false unless channel_match?(trigger, event)

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

      def channel_match?(trigger, event)
        return true unless trigger.key?(:channel)

        event.channel.to_i == trigger[:channel].to_i
      end

      def invoke_action_block(context, action, value)
        if action.arity.zero?
          context.instance_exec(&action)
        else
          context.instance_exec(value, &action)
        end
      end

      def event_value(event, trigger)
        if trigger.key?(:note)
          event.data2.to_i.clamp(0, 127)
        elsif trigger.key?(:cc)
          cc_event_value(event, trigger)
        elsif trigger.key?(:pc)
          event.data1.to_i.clamp(0, 127)
        else
          0
        end
      end

      def cc_event_value(event, trigger)
        raw = event.data2.to_i.clamp(0, 127)
        state = (@cc_state[state_key(trigger)] ||= {})
        value = trigger[:relative] ? relative_cc_delta(raw) : raw
        return nil if pickup_blocked?(raw, state, trigger)
        return nil if within_deadband?(value, state, trigger)

        value = smooth_value(value, state, trigger)
        state[:last_raw] = raw unless trigger[:relative]
        state[:last_value] = value
        value
      end

      def relative_cc_delta(raw)
        return raw if raw.between?(1, 63)
        return raw - 128 if raw.between?(65, 127)

        0
      end

      def pickup_blocked?(raw, state, trigger)
        return false unless trigger[:pickup]
        return false unless trigger.key?(:cc)
        return false if state[:pickup_synced]

        return false if trigger[:relative]

        reference = state[:pickup_reference_raw]
        unless reference
          state[:pickup_reference_raw] = raw
          return true
        end

        tolerance = trigger[:deadband] || 1
        if (raw - reference).abs <= tolerance
          state[:pickup_synced] = true
          state[:pickup_reference_raw] = nil
          return false
        end

        true
      end

      def within_deadband?(value, state, trigger)
        return false unless trigger.key?(:deadband)

        deadband = Float(trigger[:deadband])
        if trigger[:relative]
          value.abs <= deadband
        elsif state.key?(:last_raw)
          (value - state[:last_raw].to_f).abs <= deadband
        else
          false
        end
      rescue ArgumentError, TypeError
        false
      end

      def smooth_value(value, state, trigger)
        return value unless trigger.key?(:smooth)
        return value unless state.key?(:last_value)

        alpha = Float(trigger[:smooth]).clamp(0.0, 1.0)
        state[:last_value].to_f + ((value - state[:last_value].to_f) * alpha)
      rescue ArgumentError, TypeError
        value
      end

      def state_key(trigger)
        [trigger[:channel], trigger[:cc]]
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

      # Runtime DSL context used while executing one `midi_map` action block.
      # @api private
      class ActionContext
        # Collected runtime actions emitted by DSL calls.
        attr_reader :actions
        attr_reader :unknown_scene_names

        # @param scenes [Hash]
        # @param globals [Hash]
        def initialize(scenes:, globals:)
          @scenes = scenes
          @globals = globals
          @actions = []
          @unknown_scene_names = []
        end

        # @param name [Symbol, String]
        # @param effect [Hash, nil]
        # @return [void]
        def switch_scene(name, effect: nil)
          scene = @scenes[name.to_sym]
          unless scene
            unknown = name.to_s
            @unknown_scene_names << unknown unless @unknown_scene_names.include?(unknown)
            return
          end

          @actions << {
            type: :switch_scene,
            scene: {
              name: scene[:name],
              layers: scene[:layers].map { |layer| deep_dup(layer) }
            },
            effect: deep_dup(effect)
          }
        end

        # Advance to the next scene in runtime scene order.
        #
        # @param effect [Hash, nil]
        # @return [void]
        def next_scene(effect: nil)
          @actions << { type: :next_scene, effect: deep_dup(effect) }
        end

        # Move to the previous scene in runtime scene order.
        #
        # @param effect [Hash, nil]
        # @return [void]
        def previous_scene(effect: nil)
          @actions << { type: :previous_scene, effect: deep_dup(effect) }
        end

        # @param key [Symbol, String]
        # @param value [Object]
        # @return [void]
        def set(key, value)
          symbol_key = key.to_sym
          @globals[symbol_key] = value
          @actions << {
            type: :set_global,
            key: symbol_key,
            value: value
          }
        end

        # @param control [Symbol, String]
        # @param value [Boolean, nil] target value; nil defaults to true for direct calls
        # @param fade [Numeric, nil] optional seconds for transition to `value == true`
        # @param release [Numeric, nil] optional seconds for transition to `value == false`
        # @return [void]
        def live_control(control, value = nil, fade: nil, release: nil, color: nil)
          state = normalize_live_control_state(value)
          state[:fade] = normalize_control_transition(fade)
          state[:release] = normalize_control_transition(release)
          state[:color] = normalize_control_color(color)
          state.delete(:fade) if state[:fade].nil?
          state.delete(:release) if state[:release].nil?
          state.delete(:color) if state[:color].nil?

          @actions << {
            type: :live_control,
            control: control.to_s,
            **state
          }
        end

        # @param value [Boolean, nil]
        # @return [void]
        def blackout(value = nil, fade: nil, release: nil, color: nil)
          live_control(:blackout, value, fade: fade, release: release, color: color)
        end

        # @param value [Boolean, nil]
        # @return [void]
        def freeze(value = nil, fade: nil, release: nil)
          live_control(:freeze, value, fade: fade, release: release)
        end

        private

        def normalize_live_control_state(value)
          if value.is_a?(Hash)
            state = value.transform_keys(&:to_sym)
            enabled = state.key?(:value) ? state[:value] : true
            return {
              value: !!enabled,
              fade: normalize_control_transition(state[:fade]),
              release: normalize_control_transition(state[:release]),
              color: normalize_control_color(state[:color]),
            }
          end

          { value: !!(value.nil? || value) }
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

        def normalize_control_transition(value)
          return nil if value.nil?

          numeric = Float(value)
          return nil if numeric.negative? || !numeric.finite?

          numeric
        rescue ArgumentError, TypeError
          nil
        end

        def normalize_control_color(value)
          return nil if value.nil?

          if value.is_a?(Array)
            return nil unless (3..4).cover?(value.length)

            channels = Array(value).map { |entry| Float(entry, exception: false) }
            return nil if channels.include?(nil)

            rgb = channels.take(3)
            alpha = channels[3]
            normalized_rgb = if rgb.all? { |channel| channel.between?(0.0, 1.0) }
              rgb
            else
              rgb.map { |channel| channel / 255.0 }
            end
            normalized = normalized_rgb.map { |channel| [0.0, [1.0, channel].min].max }
            return alpha.nil? ? normalized : normalized + [normalize_control_alpha(alpha)]
          end

          raw = value.to_s.strip
          match = raw.match(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/)
          return nil unless match

          raw_hex = match[1]
          hex = raw_hex.length == 3 || raw_hex.length == 4 ? raw_hex.chars.map { |char| "#{char}#{char}" }.join("") : raw_hex

          [
            Integer("0x#{hex[0, 2]}", 16),
            Integer("0x#{hex[2, 2]}", 16),
            Integer("0x#{hex[4, 2]}", 16),
            Integer("0x#{hex[6, 2]}", 16)
          ].take(raw_hex.length > 4 ? 4 : 3).map { |channel| [0.0, [1.0, channel / 255.0].min].max }
        rescue ArgumentError, TypeError
          nil
        end

        def normalize_control_alpha(value)
          return nil if value.nil?

          alpha = Float(value, exception: false)
          return nil if alpha.nil?

          return [0.0, [1.0, alpha].min].max if alpha.between?(0.0, 1.0)

          [0.0, [1.0, alpha / 255.0].min].max
        end
      end
    end
  end
end
