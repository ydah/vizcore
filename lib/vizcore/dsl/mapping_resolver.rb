# frozen_string_literal: true

require_relative "../deep_copy"
require_relative "../shape"

module Vizcore
  module DSL
    # Resolves `map` definitions into concrete per-layer parameter values.
    class MappingResolver
      def initialize
        @mapping_state = {}
      end

      # Clear stateful transform memory such as smoothing, hold, decay, and hysteresis.
      #
      # @return [void]
      def reset!
        @mapping_state.clear
      end

      # @param scene_layers [Array<Hash>]
      # @param audio [Hash]
      # @return [Array<Hash>] normalized layer payloads with resolved params
      def resolve_layers(scene_layers:, audio:, time: 0.0, frame: 0, resolution: [1280, 720], globals: {}, custom_shape_overrides: {}, layer_param_overrides: {})
        normalize_scene_layers(scene_layers).map do |layer|
          resolve_layer(layer, audio, time: time, frame: frame, resolution: resolution, globals: globals, custom_shape_overrides: custom_shape_overrides, layer_param_overrides: layer_param_overrides)
        end
      end

      private

      def resolve_layer(layer, audio, time:, frame:, resolution:, globals:, custom_shape_overrides:, layer_param_overrides:)
        params = deep_dup(layer[:params] || {})
        apply_custom_shape_overrides!(params, layer_name: layer[:name], custom_shape_overrides: custom_shape_overrides)
        merge_resolved_mappings!(params, resolve_mappings(layer[:mappings], audio, globals: globals, layer_name: layer[:name], time: time, frame: frame))
        apply_layer_param_overrides!(params, layer_name: layer[:name], layer_param_overrides: layer_param_overrides)
        expand_dynamic_custom_shapes!(params, layer: layer, audio: audio, time: time, frame: frame, resolution: resolution, globals: globals)

        output = {
          name: layer.fetch(:name).to_s,
          type: (layer[:type] || :geometry).to_s,
          params: params
        }
        output[:shader] = layer[:shader].to_s if layer[:shader]
        output[:glsl] = layer[:glsl].to_s if layer[:glsl]
        output[:glsl_source] = layer[:glsl_source].to_s if layer[:glsl_source]
        output[:param_schema] = Array(layer[:param_schema]).map(&:dup) if layer[:param_schema]
        output
      end

      def resolve_mappings(mappings, audio, globals:, layer_name:, time:, frame:)
        Array(mappings).each_with_object({}) do |mapping, resolved|
          source = mapping[:source]
          target = mapping[:target]
          next unless source && target

          state_key = [layer_name, target, source]
          value = resolve_source_value(
            source,
            audio,
            globals: globals,
            time: time,
            state_key: state_key,
            frame: frame
          )
          value = apply_transform(value, mapping[:transform], state_key: state_key, frame: frame)
          resolved[target.to_s] = value unless value.nil?
        end
      end

      def merge_resolved_mappings!(params, mappings)
        mappings.each do |target, value|
          if target.include?(".")
            assign_nested_param(params, target.split("."), value)
          else
            params[target.to_sym] = value
          end
        end
      end

      def expand_dynamic_custom_shapes!(params, layer:, audio:, time:, frame:, resolution:, globals:)
        descriptors = Array(params.delete(:custom_shapes) || params.delete("custom_shapes"))
        return if descriptors.empty?

        params[:shapes] = Array(params[:shapes])
        controls = []
        descriptors.each_with_index do |descriptor, index|
          start_index = params[:shapes].length
          expanded = expand_dynamic_custom_shape(descriptor, layer: layer, palette: params[:palette], audio: audio, time: time, frame: frame, resolution: resolution, globals: globals)
          params[:shapes].concat(expanded)
          controls << custom_shape_control_descriptor(descriptor, index: index, start_index: start_index, count: expanded.length)
        end
        params[:custom_shape_controls] = controls unless controls.empty?
      end

      def expand_dynamic_custom_shape(descriptor, layer:, palette:, audio:, time:, frame:, resolution:, globals:)
        values = Hash(descriptor)
        renderer = values.fetch(:renderer)
        shape_name = values[:name] || renderer
        primitives = Vizcore::Shape.expand_custom_shape(
          renderer,
          params: Hash(values[:params] || {}),
          shape_id: values[:shape_id],
          layer_name: layer[:name],
          palette: Array(palette),
          audio: audio,
          time: time,
          frame: frame,
          resolution: resolution,
          globals: globals,
          shape_name: shape_name
        )
        primitives.each { |primitive| apply_custom_shape_attributes!(primitive, values) }
      end

      def custom_shape_control_descriptor(descriptor, index:, start_index:, count:)
        values = Hash(descriptor)
        {
          index: index,
          name: (values[:name] || values["name"] || "custom_shape").to_s,
          params: deep_dup(Hash(values[:params] || values["params"] || {})),
          param_schema: Array(values[:param_schema] || values["param_schema"]).map { |entry| deep_dup(entry) },
          shape_indices: (start_index...(start_index + count)).to_a
        }
      end

      def apply_custom_shape_overrides!(params, layer_name:, custom_shape_overrides:)
        layer_overrides = custom_shape_layer_overrides(custom_shape_overrides, layer_name)
        return if layer_overrides.empty?

        descriptors = Array(params[:custom_shapes] || params["custom_shapes"])
        layer_overrides.each do |index, values|
          descriptor = descriptors[Integer(index)]
          next unless descriptor && values.is_a?(Hash)

          descriptor[:params] ||= {}
          values.each do |param_name, value|
            key = param_name.to_sym
            descriptor[:params][key] = value
          end
        rescue ArgumentError, TypeError
          next
        end
      end

      def custom_shape_layer_overrides(overrides, layer_name)
        values = Hash(overrides)
        name = layer_name.to_s
        Hash(values[name] || values[layer_name.to_sym] || {})
      rescue TypeError
        {}
      end

      def apply_layer_param_overrides!(params, layer_name:, layer_param_overrides:)
        layer_overrides = custom_shape_layer_overrides(layer_param_overrides, layer_name)
        layer_overrides.each do |target, value|
          target_name = target.to_s
          if target_name.include?(".")
            assign_nested_param(params, target_name.split("."), value)
          else
            params[target_name.to_sym] = value
          end
        end
      end

      def apply_custom_shape_attributes!(primitive, descriptor)
        style = Hash(descriptor[:style] || {})
        style.each do |key, value|
          symbol_key = key.to_sym
          if symbol_key == :opacity && primitive.key?(:opacity)
            primitive[:opacity] = numeric(style[:opacity] || style["opacity"], :opacity) * numeric(primitive[:opacity], :opacity)
          else
            primitive[symbol_key] = deep_dup(value) unless primitive.key?(symbol_key)
          end
        end

        transform = Hash(descriptor[:transform] || {})
        primitive[:transform] = compose_shape_transform(transform, primitive[:transform]) unless transform.empty?
        primitive
      end

      def assign_nested_param(container, path, value)
        key = path.shift
        if path.empty?
          assign_nested_value(container, key, value)
          return
        end

        next_container = nested_value(container, key)
        next_container = create_nested_container(container, key, path.first) if next_container.nil?
        return unless next_container

        assign_nested_param(next_container, path, value)
      end

      def nested_value(container, key)
        return container[key.to_i] if container.is_a?(Array) && integer_key?(key)
        return container[key.to_sym] if container.is_a?(Hash)

        nil
      end

      def create_nested_container(container, key, next_key)
        return unless container.is_a?(Hash)

        value = integer_key?(next_key) ? [] : {}
        container[key.to_sym] = value
      end

      def assign_nested_value(container, key, value)
        if container.is_a?(Array) && integer_key?(key)
          container[key.to_i] = value
        elsif container.is_a?(Hash)
          container[key.to_sym] = value
        end
      end

      def integer_key?(value)
        value.match?(/\A\d+\z/)
      end

      def compose_shape_transform(parent, child)
        return deep_dup(child || {}) unless parent

        child ||= {}
        output = deep_dup(parent)
        output[:translate] = add_shape_xy(parent[:translate], child[:translate]) if child.key?(:translate)
        output[:origin] = child[:origin] if child.key?(:origin)
        output[:rotate] = numeric(parent[:rotate] || 0, :rotate) + numeric(child[:rotate] || 0, :rotate) if child.key?(:rotate)
        output[:scale] = multiply_shape_scale(parent[:scale], child[:scale]) if child.key?(:scale)
        output
      end

      def add_shape_xy(parent, child)
        parent ||= {}
        child ||= {}
        {
          x: numeric(parent[:x] || parent["x"] || 0, :"translate.x") + numeric(child[:x] || child["x"] || 0, :"translate.x"),
          y: numeric(parent[:y] || parent["y"] || 0, :"translate.y") + numeric(child[:y] || child["y"] || 0, :"translate.y")
        }
      end

      def multiply_shape_scale(parent, child)
        parent = shape_scale_pair(parent)
        child = shape_scale_pair(child)
        { x: parent[:x] * child[:x], y: parent[:y] * child[:y] }
      end

      def shape_scale_pair(value)
        return { x: numeric(value[:x] || value["x"] || 1, :"scale.x"), y: numeric(value[:y] || value["y"] || 1, :"scale.y") } if value.is_a?(Hash)

        scale = numeric(value || 1, :scale)
        { x: scale, y: scale }
      end

      def numeric(value, name)
        Float(value)
      rescue ArgumentError, TypeError
        raise ArgumentError, "param #{name} must be numeric"
      end

      def resolve_source_value(source, audio, globals: {}, time: 0.0, state_key: nil, frame: 0)
        return 0.0 unless source

        case source[:kind]&.to_sym
        when :amplitude
          audio[:amplitude]
        when :peak
          audio[:peak]
        when :frequency_band
          audio.dig(:bands, source[:band]&.to_sym)
        when :frequency_band_peak
          audio.dig(:band_peaks, source[:band]&.to_sym)
        when :fft_spectrum
          audio[:fft]
        when :onset
          resolve_onset(source, audio)
        when :kick, :snare, :hihat
          audio.dig(:drums, source[:kind].to_sym)
        when :beat
          audio[:beat]
        when :beat_confidence
          audio[:beat_confidence]
        when :beat_pulse
          audio[:beat_pulse]
        when :beat_count
          audio[:beat_count]
        when :beat_phase
          audio[:beat_phase]
        when :beat_2
          audio[:beat_2]
        when :beat_4
          audio[:beat_4]
        when :beat_8
          audio[:beat_8]
        when :beat_triplet, :triplet
          audio[:beat_triplet]
        when :bar_phase
          audio[:bar_phase]
        when :bar_count
          audio[:bar_count]
        when :phrase_count
          audio[:phrase_count]
        when :bpm
          audio[:bpm]
        when :bpm_confidence
          audio[:bpm_confidence]
        when :spectral_centroid
          audio[:spectral_centroid]
        when :spectral_rolloff
          audio[:spectral_rolloff]
        when :spectral_flatness
          audio[:spectral_flatness]
        when :spectral_flux
          audio[:spectral_flux]
        when :zero_crossing_rate
          audio[:zero_crossing_rate]
        when :global
          resolve_global(source, globals)
        when :lfo
          resolve_lfo(source, time)
        when :adsr, :envelope
          resolve_envelope(source, audio, globals: globals, time: time, state_key: state_key, frame: frame)
        else
          nil
        end
      end

      def resolve_envelope(source, audio, globals: {}, time: 0.0, state_key:, frame:)
        state = envelope_state(state_key)
        params = envelope_params(source)
        nested = source[:source] || :kick
        normalized_nested = normalize_source_descriptor(nested)
        trigger_value = resolve_nested_source_value(normalized_nested, audio, globals: globals, time: time)
        trigger = trigger_numeric(trigger_value)

        now = normalized_time(time)
        state[:time] = now
        state[:last_frame] = frame
        state[:gate] = trigger > params[:threshold]
        state[:note_on] = state[:gate]

        peak = normalize_envelope_peak(params.fetch(:peak)) * trigger
        if state[:gate]
          if state[:phase] == :idle || state[:phase] == :release
            state[:phase] = :attack
            state[:phase_started_at] = now
            state[:phase_start_value] = state[:value]
            state[:peak] = peak
          else
            state[:peak] = [state[:peak], peak].max
          end
        end

        state[:value], state[:phase] = next_envelope_step(
          state,
          params: params,
          now: now
        )
        state[:value]
      rescue StandardError
        0.0
      ensure
        @mapping_state[state_key] = state if state_key
      end

      def resolve_nested_source_value(source, audio, globals:, time:)
        return resolve_source_value({ kind: :amplitude }, audio, globals: globals, time: time) if source.nil?

        nested_kind = source[:kind]&.to_sym
        return 0.0 if nested_kind == :adsr || nested_kind == :envelope

        resolve_source_value(source, audio, globals: globals, time: time)
      rescue StandardError
        0.0
      end

      def normalize_source_descriptor(source)
        return source if source.is_a?(Hash) && source[:kind]

        { kind: source.to_sym }
      rescue StandardError
        nil
      end

      def resolve_lfo(source, time)
        rate = Float(source[:rate] || 1.0)
        phase = Float(source[:phase] || 0.0)
        position = (Float(time) * rate + phase) % 1.0
        case source[:wave]&.to_sym
        when :triangle
          1.0 - ((position * 2.0) - 1.0).abs
        when :saw
          position
        when :square
          position < 0.5 ? 1.0 : 0.0
        else
          (Math.sin(position * Math::PI * 2.0) + 1.0) * 0.5
        end
      rescue ArgumentError, TypeError
        0.0
      end

      def resolve_global(source, globals)
        name = source[:name]&.to_sym
        return nil unless name

        values = Hash(globals || {})
        values[name] || values[name.to_s]
      rescue StandardError
        nil
      end

      def envelope_state(state_key)
        return {} unless state_key

        @mapping_state[state_key] ||= {
          phase: :idle,
          value: 0.0,
          peak: 0.0,
          phase_started_at: 0.0,
          phase_start_value: 0.0,
          time: 0.0,
          note_on: false,
          gate: false
        }
      end

      def envelope_params(source)
        {
          attack: Float(source[:attack] || 0.02),
          decay: Float(source[:decay] || 0.08),
          sustain: Float(source[:sustain] || 0.7).clamp(0.0, 1.0),
          release: Float(source[:release] || 0.16),
          threshold: Float(source[:threshold] || 0.0),
          peak: Float(source[:peak] || 1.0)
        }
      rescue StandardError
        { attack: 0.02, decay: 0.08, sustain: 0.7, release: 0.16, threshold: 0.0, peak: 1.0 }
      end

      def normalized_time(value)
        numeric = Float(value)
        numeric.nan? ? 0.0 : numeric
      rescue StandardError
        0.0
      end

      def normalize_envelope_peak(value)
        value = Float(value)
        value.nan? ? 1.0 : value
      rescue StandardError
        1.0
      end

      def next_envelope_step(state, params:, now:)
        phase = state[:phase] || :idle
        if phase == :attack
          return [state[:peak], :sustain] if params[:attack] <= 0.0

          elapsed = now - state[:phase_started_at]
          if elapsed >= params[:attack]
            state[:phase_started_at] = now
            state[:phase_start_value] = state[:peak]
            return [state[:peak], :decay]
          end

          ratio = [elapsed / params[:attack], 1.0].min
          value = state[:phase_start_value] + (state[:peak] - state[:phase_start_value]) * ratio
          return [value, :attack]
        end

        if phase == :decay
          return [state[:peak] * params[:sustain], :sustain] if params[:decay] <= 0.0

          elapsed = now - state[:phase_started_at]
          target = state[:peak] * params[:sustain]
          if elapsed >= params[:decay]
            state[:phase_started_at] = now
            state[:phase_start_value] = target
            return [target, :sustain]
          end

          ratio = [elapsed / params[:decay], 1.0].min
          value = state[:phase_start_value] + (target - state[:phase_start_value]) * ratio
          return [value, :decay]
        end

        if phase == :sustain
          return state[:phase_start_value], :sustain if state[:gate]

          state[:phase] = :release
          state[:phase_started_at] = now
          state[:phase_start_value] = state[:value]
          return [state[:value], :release]
        end

        if phase == :release
          return [0.0, :idle] if params[:release] <= 0.0

          elapsed = now - state[:phase_started_at]
          target = 0.0
          if elapsed >= params[:release]
            state[:phase_started_at] = now
            state[:phase_start_value] = 0.0
            return [0.0, :idle]
          end

          ratio = [elapsed / params[:release], 1.0].min
          value = state[:phase_start_value] * (1.0 - ratio)
          return [value, :release]
        end

        if phase == :idle
          return [0.0, :idle] unless state[:gate] && params[:attack] > 0.0

          state[:phase_started_at] = now
          state[:phase_start_value] = 0.0
          state[:peak] = state[:peak]
          return [0.0, :attack]
        end

        [0.0, :idle]
      end

      def trigger_numeric(value)
        return 0.0 if value == false || value == 0
        return 1.0 if value == true
        return 0.0 if value.nil?

        Float(value)
      rescue StandardError
        0.0
      end

      def resolve_onset(source, audio)
        band = source[:band]&.to_sym
        return audio[:onset] unless band

        audio.dig(:onsets, band)
      end

      def apply_transform(value, transform, state_key:, frame:)
        return value if transform.nil? || transform.empty?
        return transform_array(value, transform) if value.is_a?(Array)
        return nil if value.is_a?(Hash) || value.nil?

        transformed = transform_scalar(value, transform, state_key: state_key)
        return nil if transformed.nil?

        transformed = apply_trigger_mode(transformed, transform, state_key: state_key) if transform[:as] == :trigger
        transformed = apply_event_shaping(transformed, transform, state_key: state_key, frame: frame)
        return apply_smoothing(transformed, transform, state_key) unless transform[:as] == :trigger
        transformed
      end

      def transform_array(value, transform)
        value.map do |entry|
          transform_scalar(entry, transform, fallback: 0.0) || 0.0
        end
      end

      def transform_scalar(value, transform, fallback: nil, state_key: nil)
        numeric = numeric_value(value, fallback: fallback)
        return nil if numeric.nil?

        numeric = 0.0 if transform.key?(:deadzone) && numeric.abs < Float(transform[:deadzone])
        numeric = apply_threshold(numeric, transform, state_key: state_key)
        numeric *= Float(transform[:gain]) if transform.key?(:gain)
        numeric = apply_curve(numeric, transform[:curve]) if transform[:curve]
        numeric = [numeric, Float(transform[:min])].max if transform.key?(:min)
        numeric = [numeric, Float(transform[:max])].min if transform.key?(:max)
        numeric
      end

      def apply_threshold(value, transform, state_key:)
        return value unless transform.key?(:threshold) || transform.key?(:hysteresis)

        threshold = Float(transform.fetch(:threshold, 0.5))
        hysteresis = Float(transform.fetch(:hysteresis, 0.0))
        return value >= threshold ? value : 0.0 if hysteresis <= 0.0 || state_key.nil?

        key = [:hysteresis, state_key]
        active = !!@mapping_state[key]
        active = value >= (active ? threshold - hysteresis : threshold)
        @mapping_state[key] = active
        active ? value : 0.0
      end

      def numeric_value(value, fallback:)
        return value ? 1.0 : 0.0 if value == true || value == false

        Float(value)
      rescue ArgumentError, TypeError
        fallback
      end

      def apply_curve(value, curve)
        case curve.to_sym
        when :linear
          value
        when :sqrt
          Math.sqrt([value, 0.0].max)
        when :square
          value * value
        when :ease_out
          clamped = [[value, 0.0].max, 1.0].min
          1.0 - ((1.0 - clamped) * (1.0 - clamped))
        when :ease_in
          clamped = [[value, 0.0].max, 1.0].min
          clamped * clamped
        when :ease_in_out
          clamped = [[value, 0.0].max, 1.0].min
          clamped < 0.5 ? 2.0 * clamped * clamped : 1.0 - ((-2.0 * clamped + 2.0)**2 / 2.0)
        when :smoothstep
          clamped = [[value, 0.0].max, 1.0].min
          clamped * clamped * (3.0 - 2.0 * clamped)
        when :exp
          clamped = [[value, 0.0].max, 1.0].min
          ((Math.exp(clamped) - 1.0) / (Math::E - 1.0)).clamp(0.0, 1.0)
        when :log
          clamped = [[value, 0.0].max, 1.0].min
          Math.log1p(clamped * (Math::E - 1.0))
        when :step
          value >= 0.5 ? 1.0 : 0.0
        end
      end

      def apply_trigger_mode(value, _transform, state_key:)
        key = [:trigger, state_key]
        active = value.to_f > 0.0
        previous = !!@mapping_state[key]
        @mapping_state[key] = active
        (active && !previous) ? 1.0 : 0.0
      end

      def apply_event_shaping(value, transform, state_key:, frame:)
        shaped = value
        shaped = apply_cooldown(shaped, transform, state_key: state_key, frame: frame) if transform.key?(:cooldown)
        shaped = apply_one_shot(shaped, transform, state_key: state_key) if transform[:one_shot]
        shaped = apply_hold(shaped, transform, state_key: state_key, frame: frame) if transform.key?(:hold)
        shaped = apply_decay(shaped, transform, state_key: state_key) if transform.key?(:decay)
        shaped
      end

      def apply_cooldown(value, transform, state_key:, frame:)
        cooldown_frames = (Float(transform[:cooldown]) * 60.0).ceil
        return value unless cooldown_frames.positive?

        key = [:cooldown, state_key]
        state = @mapping_state[key] || { until_frame: 0 }
        current_frame = Integer(frame)
        return value unless value.to_f > 0.0

        if current_frame >= state[:until_frame]
          state[:until_frame] = current_frame + cooldown_frames
          @mapping_state[key] = state
          value
        else
          0.0
        end
      rescue StandardError
        value
      end

      def apply_one_shot(value, _transform, state_key:)
        key = [:one_shot, state_key]

        active = value.to_f > 0.0
        return 0.0 unless active

        fired = !!@mapping_state[key]
        return 0.0 if fired

        @mapping_state[key] = true
        value
      rescue StandardError
        value
      end

      def apply_hold(value, transform, state_key:, frame:)
        hold_frames = (Float(transform[:hold]) * 60.0).ceil
        return value unless hold_frames.positive?

        key = [:hold, state_key]
        state = @mapping_state[key] || { until_frame: -1, value: 0.0 }
        current_frame = Integer(frame)
        if value.to_f.positive?
          state = { until_frame: current_frame + hold_frames, value: value }
        elsif current_frame <= state[:until_frame]
          value = state[:value]
        end
        @mapping_state[key] = state
        value
      rescue StandardError
        value
      end

      def apply_decay(value, transform, state_key:)
        decay = Float(transform[:decay]).clamp(0.0, 1.0)
        key = [:decay, state_key]
        previous = @mapping_state[key].to_f
        output = [value.to_f, previous * decay].max
        @mapping_state[key] = output
        output
      rescue StandardError
        value
      end

      def apply_smoothing(value, transform, state_key)
        return value unless transform.key?(:attack) || transform.key?(:release)

        state_key = [:smooth, state_key]
        previous = @mapping_state[state_key]
        if previous.nil?
          @mapping_state[state_key] = value
          return value
        end

        alpha = value >= previous ? transform.fetch(:attack, 1.0) : transform.fetch(:release, 1.0)
        smoothed = previous + (value - previous) * alpha
        @mapping_state[state_key] = smoothed
        smoothed
      end

      def normalize_scene_layers(scene_layers)
        Array(scene_layers).map { |layer| deep_symbolize(layer) }
      end

      def deep_dup(value)
        Vizcore::DeepCopy.copy(value)
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, entry), output|
            output[key.to_sym] = deep_symbolize(entry)
          end
        when Array
          value.map { |entry| deep_symbolize(entry) }
        else
          value
        end
      end
    end
  end
end
