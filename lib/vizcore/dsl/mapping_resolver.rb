# frozen_string_literal: true

require_relative "../shape"

module Vizcore
  module DSL
    # Resolves `map` definitions into concrete per-layer parameter values.
    class MappingResolver
      def initialize
        @mapping_state = {}
      end

      # @param scene_layers [Array<Hash>]
      # @param audio [Hash]
      # @return [Array<Hash>] normalized layer payloads with resolved params
      def resolve_layers(scene_layers:, audio:, time: 0.0, frame: 0, resolution: [1280, 720], globals: {}, custom_shape_overrides: {})
        normalize_scene_layers(scene_layers).map do |layer|
          resolve_layer(layer, audio, time: time, frame: frame, resolution: resolution, globals: globals, custom_shape_overrides: custom_shape_overrides)
        end
      end

      private

      def resolve_layer(layer, audio, time:, frame:, resolution:, globals:, custom_shape_overrides:)
        params = deep_dup(layer[:params] || {})
        apply_custom_shape_overrides!(params, layer_name: layer[:name], custom_shape_overrides: custom_shape_overrides)
        merge_resolved_mappings!(params, resolve_mappings(layer[:mappings], audio, layer_name: layer[:name], frame: frame))
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

      def resolve_mappings(mappings, audio, layer_name:, frame:)
        Array(mappings).each_with_object({}) do |mapping, resolved|
          source = mapping[:source]
          target = mapping[:target]
          next unless source && target

          value = resolve_source_value(source, audio)
          value = apply_transform(value, mapping[:transform], state_key: [layer_name, target, source], frame: frame)
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

      def resolve_source_value(source, audio)
        case source[:kind]&.to_sym
        when :amplitude
          audio[:amplitude]
        when :peak
          audio[:peak]
        when :frequency_band
          audio.dig(:bands, source[:band]&.to_sym)
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
        else
          nil
        end
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

        transformed = apply_event_shaping(transformed, transform, state_key: state_key, frame: frame)
        apply_smoothing(transformed, transform, state_key)
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

      def apply_event_shaping(value, transform, state_key:, frame:)
        shaped = value
        shaped = apply_hold(shaped, transform, state_key: state_key, frame: frame) if transform.key?(:hold)
        shaped = apply_decay(shaped, transform, state_key: state_key) if transform.key?(:decay)
        shaped
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
