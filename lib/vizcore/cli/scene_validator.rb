# frozen_string_literal: true

require "set"
require_relative "../../vizcore"
require_relative "../dsl"
require_relative "../layer_catalog"

module Vizcore
  module CLISupport
    # Validates scene DSL files without starting the realtime server.
    class SceneValidator
      BUILTIN_SHADERS = Vizcore::LayerCatalog::BUILTIN_SHADERS

      MAPPING_SOURCE_KINDS = %i[
        amplitude peak frequency_band frequency_band_peak fft_spectrum onset kick snare hihat beat beat_confidence beat_pulse beat_count bpm
        beat_phase beat_2 beat_4 beat_8 beat_triplet triplet bar_phase bar_count phrase_count bpm_confidence
        spectral_centroid spectral_rolloff spectral_flatness spectral_flux zero_crossing_rate global lfo
      ].freeze

      LFO_WAVES = %i[sine triangle saw square].freeze
      FREQUENCY_BANDS = %i[sub low mid high].freeze
      SUPPORTED_BLEND_MODES = Vizcore::LayerCatalog::BLEND_MODES
      SUPPORTED_POST_EFFECTS = Vizcore::LayerCatalog::POST_EFFECTS
      SUPPORTED_VJ_EFFECTS = Vizcore::LayerCatalog::VJ_EFFECTS
      SUPPORTED_SHAPE_KINDS = %i[circle line rect polygon polyline path star].freeze
      STRICT_PARAM_ALLOWLIST = Vizcore::DSL::LayerBuilder::STRICT_PARAM_ALLOWLIST

      Issue = Struct.new(:severity, :code, :message, keyword_init: true) do
        def error?
          severity == :error
        end

        def to_h
          { severity: severity, code: code, message: message }
        end
      end

      Result = Struct.new(:definition, :issues, keyword_init: true) do
        def valid?
          issues.none?(&:error?)
        end

        def errors
          issues.select(&:error?)
        end

        def warnings
          issues.reject(&:error?)
        end
      end

      def initialize(scene_file:, loader: Vizcore::DSL::Engine.method(:load_file), shader_resolver: Vizcore::DSL::ShaderSourceResolver.new, strict: false)
        @scene_file = scene_file
        @loader = loader
        @shader_resolver = shader_resolver
        @strict = !!strict
      end

      def call
        definition = load_definition
        Result.new(definition: definition, issues: validate_definition(definition))
      rescue StandardError => e
        Result.new(
          definition: nil,
          issues: [error("failed to load scene: #{e.message}", code: "E_SCENE_LOAD")]
        )
      end

      private

      def load_definition
        definition = @loader.call(@scene_file)
        @shader_resolver.resolve(definition: definition, scene_file: @scene_file)
      end

      def validate_definition(definition)
        issues = []
        scenes = Array(definition[:scenes])
        validate_scenes(scenes, issues)
        names = scene_names(scenes)
        validate_transitions(Array(definition[:transitions]), names, issues)
        validate_timelines(Array(definition[:timelines]), names, issues)
        validate_key_mappings(Array(definition[:key_mappings]), names, issues)
        validate_midi_maps(Array(definition[:midi_maps]), issues)
        issues
      end

      def validate_scenes(scenes, issues)
        issues << error("no scenes defined", code: "E_NO_SCENES") if scenes.empty?
        duplicate_values(scenes.filter_map { |scene| scene[:name]&.to_sym }).each do |name|
          issues << error("duplicate scene name: #{name}", code: "E_DUPLICATE_SCENE")
        end

        scenes.each do |scene|
          scene_name = scene[:name] || "(unnamed)"
          layers = Array(scene[:layers])
          issues << warn("scene #{scene_name} has no layers; frontend will render the default geometry", code: "W_EMPTY_SCENE") if layers.empty?
          validate_layers(layers, scene_name, issues)
        end
      end

      def validate_layers(layers, scene_name, issues)
        duplicate_values(layers.filter_map { |layer| layer[:name]&.to_sym }).each do |name|
          issues << error("scene #{scene_name} has duplicate layer name: #{name}", code: "E_DUPLICATE_LAYER")
        end

        layers.each do |layer|
          validate_layer(layer, scene_name, issues)
        end
      end

      def validate_layer(layer, scene_name, issues)
        layer_name = layer[:name] || "(unnamed)"
        type = layer[:type]&.to_sym || :geometry
        unless supported_layer_types.include?(type)
          issues << error("scene #{scene_name} layer #{layer_name} has unsupported type: #{type}", code: "E_UNKNOWN_LAYER_TYPE")
        end

        shader = layer[:shader]&.to_sym
        if shader && !BUILTIN_SHADERS.include?(shader)
          issues << error("scene #{scene_name} layer #{layer_name} uses unknown shader: #{shader}", code: "E_UNKNOWN_SHADER")
        end

        glsl_source = layer[:glsl_source]
        issues << warn("scene #{scene_name} layer #{layer_name} has an empty GLSL file", code: "W_EMPTY_GLSL") if layer[:glsl] && glsl_source.to_s.empty?
        validate_unknown_layer_params(layer, scene_name, layer_name, type, issues) if @strict || layer[:strict]
        validate_blend_mode(layer, scene_name, layer_name, issues)
        validate_layer_effects(layer, scene_name, layer_name, issues)
        validate_shape_layer(layer, scene_name, layer_name, issues)
        validate_mappings(Array(layer[:mappings]), layer, scene_name, layer_name, issues)
      end

      def validate_blend_mode(layer, scene_name, layer_name, issues)
        blend = layer.dig(:params, :blend)
        return unless blend
        return if SUPPORTED_BLEND_MODES.include?(blend.to_sym)

        issues << error("scene #{scene_name} layer #{layer_name} uses unsupported blend mode: #{blend}", code: "E_UNSUPPORTED_BLEND")
      end

      def validate_layer_effects(layer, scene_name, layer_name, issues)
        params = layer[:params] || {}
        validate_effect_name(params[:effect], SUPPORTED_POST_EFFECTS, "effect", scene_name, layer_name, issues)
        validate_effect_name(params[:vj_effect], SUPPORTED_VJ_EFFECTS, "vj_effect", scene_name, layer_name, issues)
      end

      def validate_shape_layer(layer, scene_name, layer_name, issues)
        params = layer[:params] || {}
        return unless shape_layer?(layer) || shape_value(params, :shapes)

        shapes = Array(shape_value(params, :shapes))
        duplicate_values(shapes.filter_map { |shape| shape_value(shape_hash(shape), :id)&.to_sym }).each do |id|
          issues << error("scene #{scene_name} layer #{layer_name} has duplicate shape id: #{id}", code: "E_DUPLICATE_SHAPE")
        end

        shapes.each_with_index do |shape, index|
          values = shape_hash(shape)
          label = shape_label(values, index)
          validate_shape_kind(values, label, scene_name, layer_name, issues)
          validate_shape_fallback_fill(values, label, scene_name, layer_name, issues)
          validate_shape_opacity(values, label, scene_name, layer_name, issues)
          validate_shape_scale(values, label, scene_name, layer_name, issues)
        end
      end

      def validate_shape_kind(shape, label, scene_name, layer_name, issues)
        kind = shape_value(shape, :kind)&.to_sym
        return if SUPPORTED_SHAPE_KINDS.include?(kind)

        issues << warn("scene #{scene_name} layer #{layer_name} shape #{label} uses unsupported kind: #{kind || "missing"}", code: "W_UNSUPPORTED_SHAPE_KIND")
      end

      def validate_shape_fallback_fill(shape, label, scene_name, layer_name, issues)
        fill = shape_value(shape, :fill)
        return if fill.nil? || fill.to_s.empty?

        issues << warn("scene #{scene_name} layer #{layer_name} shape #{label} fill may be ignored by line fallback", code: "W_SHAPE_FILL_FALLBACK")
      end

      def validate_shape_opacity(shape, label, scene_name, layer_name, issues)
        opacity = numeric_shape_value(shape_value(shape, :opacity))
        return unless opacity && (opacity.negative? || opacity > 1)

        issues << warn("scene #{scene_name} layer #{layer_name} shape #{label} opacity #{opacity} is outside 0..1; renderer will clamp", code: "W_SHAPE_OPACITY_RANGE")
      end

      def validate_shape_scale(shape, label, scene_name, layer_name, issues)
        scale_values(shape).each do |scale|
          next unless scale

          if scale.zero?
            issues << warn("scene #{scene_name} layer #{layer_name} shape #{label} scale includes 0; shape may collapse", code: "W_SHAPE_ZERO_SCALE")
          elsif scale.abs > 8
            issues << warn("scene #{scene_name} layer #{layer_name} shape #{label} scale #{scale} is extreme; renderer will clamp", code: "W_SHAPE_EXTREME_SCALE")
          end
        end
      end

      def supported_layer_types
        Vizcore::LayerCatalog.supported_types
      end

      def shape_layer?(layer)
        %w[shape shapes shape_layer].include?((layer[:type] || layer["type"]).to_s)
      end

      def shape_label(shape, index)
        id = shape_value(shape, :id)
        id ? "`#{id}`" : "##{index + 1}"
      end

      def scale_values(shape)
        transform = Hash(shape_value(shape, :transform) || {})
        scale = shape_value(transform, :scale) || shape_value(shape, :scale)
        case scale
        when Hash
          [numeric_shape_value(shape_value(scale, :x)), numeric_shape_value(shape_value(scale, :y))]
        when Array
          [numeric_shape_value(scale[0]), numeric_shape_value(scale[1])]
        else
          [numeric_shape_value(scale)]
        end
      rescue TypeError
        []
      end

      def numeric_shape_value(value)
        return nil if value.nil?

        numeric = Float(value)
        numeric if numeric.finite?
      rescue ArgumentError, TypeError
        nil
      end

      def shape_hash(value)
        Hash(value)
      rescue TypeError
        {}
      end

      def shape_value(hash, key)
        hash[key] || hash[key.to_s]
      end

      def validate_effect_name(value, supported, field, scene_name, layer_name, issues)
        return unless value
        return if supported.include?(value.to_sym)

        issues << error("scene #{scene_name} layer #{layer_name} uses unsupported #{field}: #{value}", code: "E_UNSUPPORTED_#{field.to_s.upcase}")
      end

      def validate_mappings(mappings, layer, scene_name, layer_name, issues)
        duplicate_values(mappings.filter_map { |mapping| mapping[:target]&.to_sym }).each do |target|
          issues << warn("scene #{scene_name} layer #{layer_name} maps multiple sources to target: #{target}", code: "W_DUPLICATE_MAPPING_TARGET")
        end

        mappings.each do |mapping|
          source = Hash(mapping[:source] || {})
          kind = source[:kind]&.to_sym
          issues << error("scene #{scene_name} layer #{layer_name} has mapping without source kind", code: "E_MAPPING_SOURCE_MISSING") unless kind
          next unless kind

          validate_mapping_source(kind, source, scene_name, layer_name, issues)
          issues << error("scene #{scene_name} layer #{layer_name} has mapping without target", code: "E_MAPPING_TARGET_MISSING") unless mapping[:target]
          validate_mapping_target(mapping[:target], layer, scene_name, layer_name, issues)
          validate_transform(Hash(mapping[:transform] || {}), scene_name, layer_name, mapping[:target], issues)
        end
      end

      def validate_mapping_source(kind, source, scene_name, layer_name, issues)
        unless MAPPING_SOURCE_KINDS.include?(kind)
          issues << error("scene #{scene_name} layer #{layer_name} uses unsupported mapping source: #{kind}", code: "E_UNKNOWN_MAPPING_SOURCE")
        end
        validate_frequency_band(source, scene_name, layer_name, issues) if kind == :frequency_band
        validate_frequency_band(source, scene_name, layer_name, issues) if kind == :frequency_band_peak
        validate_onset_band(source, scene_name, layer_name, issues) if kind == :onset
        validate_global_source(source, scene_name, layer_name, issues) if kind == :global
        validate_lfo_source(source, scene_name, layer_name, issues) if kind == :lfo
      end

      def validate_frequency_band(source, scene_name, layer_name, issues)
        band = source[:band]&.to_sym
        return if FREQUENCY_BANDS.include?(band)

        issues << error("scene #{scene_name} layer #{layer_name} uses unsupported frequency band: #{band.inspect}", code: "E_UNKNOWN_FREQUENCY_BAND")
      end

      def validate_onset_band(source, scene_name, layer_name, issues)
        return unless source.key?(:band)

        band = source[:band]&.to_sym
        return if FREQUENCY_BANDS.include?(band)

        issues << error("scene #{scene_name} layer #{layer_name} uses unsupported onset band: #{band.inspect}", code: "E_UNKNOWN_ONSET_BAND")
      end

      def validate_global_source(source, scene_name, layer_name, issues)
        name = source[:name] || source["name"]
        return unless name.to_s.strip.empty?

        issues << error("scene #{scene_name} layer #{layer_name} uses global mapping source without name", code: "E_GLOBAL_SOURCE_NAME")
      end

      def validate_lfo_source(source, scene_name, layer_name, issues)
        wave = source[:wave] || source["wave"] || :sine
        wave_name = wave.respond_to?(:to_sym) ? wave.to_sym : nil
        unless LFO_WAVES.include?(wave_name)
          issues << error("scene #{scene_name} layer #{layer_name} uses unsupported LFO wave: #{wave}", code: "E_LFO_WAVE")
        end

        %i[rate phase].each do |key|
          value = source[key] || source[key.to_s]
          next if value.nil?

          Float(value)
        rescue ArgumentError, TypeError
          issues << error("scene #{scene_name} layer #{layer_name} has non-numeric LFO #{key}: #{value}", code: "E_LFO_#{key.to_s.upcase}")
        end
      end

      def validate_transform(transform, scene_name, layer_name, target, issues)
        return unless transform.key?(:min) && transform.key?(:max)
        return unless Float(transform[:min]) > Float(transform[:max])

        issues << error("scene #{scene_name} layer #{layer_name} mapping #{target} has min greater than max", code: "E_MAPPING_RANGE")
      rescue ArgumentError, TypeError
        issues << error("scene #{scene_name} layer #{layer_name} mapping #{target} has non-numeric min/max", code: "E_MAPPING_RANGE")
      end

      def validate_transitions(transitions, names, issues)
        transitions.each do |transition|
          from = transition[:from]&.to_sym
          to = transition[:to]&.to_sym
          issues << error("transition has unknown source scene: #{from}", code: "E_UNKNOWN_TRANSITION_SOURCE") if from && !names.include?(from)
          issues << error("transition has unknown target scene: #{to}", code: "E_UNKNOWN_TRANSITION_TARGET") if to && !names.include?(to)
          unless transition[:trigger].respond_to?(:call)
            issues << warn("transition #{from || '?'} -> #{to || '?'} has no trigger block", code: "W_TRANSITION_WITHOUT_TRIGGER")
          end
        end
      end

      def validate_timelines(timelines, names, issues)
        timelines.each do |timeline|
          Array(timeline).each do |entry|
            scene = entry[:scene]&.to_sym
            next if scene && names.include?(scene)

            issues << error("timeline references unknown scene: #{entry[:scene]}", code: "E_UNKNOWN_TIMELINE_SCENE")
          end
        end
      end

      def validate_key_mappings(mappings, names, issues)
        duplicate_values(mappings.map { |mapping| (mapping[:key] || mapping["key"]).to_s.strip.downcase }.reject(&:empty?)).each do |key|
          issues << error("duplicate key mapping: #{key}", code: "E_DUPLICATE_KEY_MAPPING")
        end

        mappings.each do |mapping|
          key = mapping[:key] || mapping["key"]
          action = mapping[:action] || mapping["action"]
          issues << error("key mapping has empty key", code: "E_KEY_EMPTY") if key.to_s.strip.empty?
          validate_key_action(action.is_a?(Hash) ? action : {}, names, key, issues)
        end
      end

      def validate_key_action(action, names, key, issues)
        type = (action[:type] || action["type"]).to_s.to_sym
        case type
        when :switch_scene
          scene = action[:scene] || action["scene"]
          scene_name = scene&.to_sym
          issues << error("key #{key} switches to unknown scene: #{scene}", code: "E_UNKNOWN_KEY_SCENE") unless scene_name && names.include?(scene_name)
        when :live_control
          control = (action[:control] || action["control"]).to_s.to_sym
          issues << error("key #{key} uses unsupported live control: #{control}", code: "E_UNKNOWN_KEY_CONTROL") unless %i[blackout freeze].include?(control)
        else
          issues << error("key #{key} has unsupported action: #{type}", code: "E_UNKNOWN_KEY_ACTION")
        end
      end

      def validate_midi_maps(mappings, issues)
        duplicate_values(mappings.filter_map { |mapping| midi_trigger_key(mapping[:trigger] || mapping["trigger"]) }).each do |trigger|
          issues << error("duplicate MIDI mapping: #{trigger}", code: "E_DUPLICATE_MIDI_MAPPING")
        end
        mappings.each do |mapping|
          validate_midi_trigger(Hash(mapping[:trigger] || mapping["trigger"] || {}), issues)
        end
      end

      def midi_trigger_key(trigger)
        values = Hash(trigger || {})
        channel = values[:channel] || values["channel"]
        channel_part = channel.nil? ? "" : ":ch#{channel}"
        %i[note cc pc].each do |key|
          value = values[key] || values[key.to_s]
          return "#{key}:#{value}#{channel_part}" unless value.nil?
        end
        nil
      rescue StandardError
        nil
      end

      def validate_midi_trigger(trigger, issues)
        channel = trigger[:channel] || trigger["channel"]
        return if channel.nil?

        value = Integer(channel)
        return if value.between?(0, 15)

        issues << error("MIDI mapping has unsupported channel: #{channel}", code: "E_MIDI_CHANNEL")
      rescue ArgumentError, TypeError
        issues << error("MIDI mapping has non-numeric channel: #{channel}", code: "E_MIDI_CHANNEL")
      end

      def validate_unknown_layer_params(layer, scene_name, layer_name, type, issues)
        params = Hash(layer[:params] || {})
        declared_params = Array(layer[:param_schema]).filter_map do |entry|
          (entry[:name] || entry["name"])&.to_sym
        end
        allowed = (Vizcore::LayerCatalog.params_for(type).keys + declared_params + STRICT_PARAM_ALLOWLIST).map(&:to_sym).uniq
        unknown = params.keys.map(&:to_sym) - allowed
        unknown.each do |param|
          issues << error("scene #{scene_name} layer #{layer_name} has unknown param in strict mode: #{param}", code: "E_UNKNOWN_LAYER_PARAM")
        end
      rescue StandardError
        nil
      end

      def validate_mapping_target(target, layer, scene_name, layer_name, issues)
        value = target.to_s
        match = /\Ashapes\.(\d+)\./.match(value)
        return unless match

        index = Integer(match[1])
        shapes = Array(shape_value(Hash(layer[:params] || {}), :shapes))
        return if index >= 0 && index < shapes.length

        issues << error("scene #{scene_name} layer #{layer_name} mapping #{target} references missing shape index", code: "E_MAPPING_TARGET")
      rescue StandardError
        issues << error("scene #{scene_name} layer #{layer_name} mapping #{target} has invalid target", code: "E_MAPPING_TARGET")
      end

      def scene_names(scenes)
        scenes.filter_map { |scene| scene[:name]&.to_sym }.to_set
      end

      def duplicate_values(values)
        counts = Hash.new(0)
        values.each { |value| counts[value] += 1 }
        counts.select { |_value, count| count > 1 }.keys
      end

      def error(message, code: "E_VALIDATION")
        Issue.new(severity: :error, code: code, message: message)
      end

      def warn(message, code: "W_VALIDATION")
        Issue.new(severity: :warn, code: code, message: message)
      end
    end
  end
end
