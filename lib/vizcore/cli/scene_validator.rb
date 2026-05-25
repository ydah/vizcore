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
        amplitude peak frequency_band fft_spectrum onset kick snare hihat beat beat_confidence beat_pulse beat_count bpm
        bpm_confidence spectral_centroid spectral_rolloff spectral_flatness spectral_flux zero_crossing_rate
      ].freeze

      FREQUENCY_BANDS = %i[sub low mid high].freeze
      SUPPORTED_BLEND_MODES = Vizcore::LayerCatalog::BLEND_MODES
      SUPPORTED_POST_EFFECTS = Vizcore::LayerCatalog::POST_EFFECTS
      SUPPORTED_VJ_EFFECTS = Vizcore::LayerCatalog::VJ_EFFECTS
      SUPPORTED_SHAPE_KINDS = %i[circle line rect polygon polyline path star].freeze

      Issue = Struct.new(:severity, :message, keyword_init: true) do
        def error?
          severity == :error
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

      def initialize(scene_file:, loader: Vizcore::DSL::Engine.method(:load_file), shader_resolver: Vizcore::DSL::ShaderSourceResolver.new)
        @scene_file = scene_file
        @loader = loader
        @shader_resolver = shader_resolver
      end

      def call
        definition = load_definition
        Result.new(definition: definition, issues: validate_definition(definition))
      rescue StandardError => e
        Result.new(
          definition: nil,
          issues: [Issue.new(severity: :error, message: "failed to load scene: #{e.message}")]
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
        validate_key_mappings(Array(definition[:key_mappings]), names, issues)
        issues
      end

      def validate_scenes(scenes, issues)
        issues << error("no scenes defined") if scenes.empty?
        duplicate_values(scenes.filter_map { |scene| scene[:name]&.to_sym }).each do |name|
          issues << error("duplicate scene name: #{name}")
        end

        scenes.each do |scene|
          scene_name = scene[:name] || "(unnamed)"
          layers = Array(scene[:layers])
          issues << warn("scene #{scene_name} has no layers; frontend will render the default geometry") if layers.empty?
          validate_layers(layers, scene_name, issues)
        end
      end

      def validate_layers(layers, scene_name, issues)
        duplicate_values(layers.filter_map { |layer| layer[:name]&.to_sym }).each do |name|
          issues << warn("scene #{scene_name} has duplicate layer name: #{name}")
        end

        layers.each do |layer|
          validate_layer(layer, scene_name, issues)
        end
      end

      def validate_layer(layer, scene_name, issues)
        layer_name = layer[:name] || "(unnamed)"
        type = layer[:type]&.to_sym || :geometry
        unless supported_layer_types.include?(type)
          issues << error("scene #{scene_name} layer #{layer_name} has unsupported type: #{type}")
        end

        shader = layer[:shader]&.to_sym
        if shader && !BUILTIN_SHADERS.include?(shader)
          issues << error("scene #{scene_name} layer #{layer_name} uses unknown shader: #{shader}")
        end

        glsl_source = layer[:glsl_source]
        issues << warn("scene #{scene_name} layer #{layer_name} has an empty GLSL file") if layer[:glsl] && glsl_source.to_s.empty?
        validate_blend_mode(layer, scene_name, layer_name, issues)
        validate_layer_effects(layer, scene_name, layer_name, issues)
        validate_shape_layer(layer, scene_name, layer_name, issues)
        validate_mappings(Array(layer[:mappings]), scene_name, layer_name, issues)
      end

      def validate_blend_mode(layer, scene_name, layer_name, issues)
        blend = layer.dig(:params, :blend)
        return unless blend
        return if SUPPORTED_BLEND_MODES.include?(blend.to_sym)

        issues << error("scene #{scene_name} layer #{layer_name} uses unsupported blend mode: #{blend}")
      end

      def validate_layer_effects(layer, scene_name, layer_name, issues)
        params = layer[:params] || {}
        validate_effect_name(params[:effect], SUPPORTED_POST_EFFECTS, "effect", scene_name, layer_name, issues)
        validate_effect_name(params[:vj_effect], SUPPORTED_VJ_EFFECTS, "vj_effect", scene_name, layer_name, issues)
      end

      def validate_shape_layer(layer, scene_name, layer_name, issues)
        params = layer[:params] || {}
        return unless shape_layer?(layer) || shape_value(params, :shapes)

        Array(shape_value(params, :shapes)).each_with_index do |shape, index|
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

        issues << warn("scene #{scene_name} layer #{layer_name} shape #{label} uses unsupported kind: #{kind || "missing"}")
      end

      def validate_shape_fallback_fill(shape, label, scene_name, layer_name, issues)
        fill = shape_value(shape, :fill)
        return if fill.nil? || fill.to_s.empty?

        issues << warn("scene #{scene_name} layer #{layer_name} shape #{label} fill may be ignored by line fallback")
      end

      def validate_shape_opacity(shape, label, scene_name, layer_name, issues)
        opacity = numeric_shape_value(shape_value(shape, :opacity))
        return unless opacity && (opacity.negative? || opacity > 1)

        issues << warn("scene #{scene_name} layer #{layer_name} shape #{label} opacity #{opacity} is outside 0..1; renderer will clamp")
      end

      def validate_shape_scale(shape, label, scene_name, layer_name, issues)
        scale_values(shape).each do |scale|
          next unless scale

          if scale.zero?
            issues << warn("scene #{scene_name} layer #{layer_name} shape #{label} scale includes 0; shape may collapse")
          elsif scale.abs > 8
            issues << warn("scene #{scene_name} layer #{layer_name} shape #{label} scale #{scale} is extreme; renderer will clamp")
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

        issues << error("scene #{scene_name} layer #{layer_name} uses unsupported #{field}: #{value}")
      end

      def validate_mappings(mappings, scene_name, layer_name, issues)
        mappings.each do |mapping|
          source = Hash(mapping[:source] || {})
          kind = source[:kind]&.to_sym
          issues << error("scene #{scene_name} layer #{layer_name} has mapping without source kind") unless kind
          next unless kind

          validate_mapping_source(kind, source, scene_name, layer_name, issues)
          issues << error("scene #{scene_name} layer #{layer_name} has mapping without target") unless mapping[:target]
          validate_transform(Hash(mapping[:transform] || {}), scene_name, layer_name, mapping[:target], issues)
        end
      end

      def validate_mapping_source(kind, source, scene_name, layer_name, issues)
        unless MAPPING_SOURCE_KINDS.include?(kind)
          issues << error("scene #{scene_name} layer #{layer_name} uses unsupported mapping source: #{kind}")
        end
        validate_frequency_band(source, scene_name, layer_name, issues) if kind == :frequency_band
        validate_onset_band(source, scene_name, layer_name, issues) if kind == :onset
      end

      def validate_frequency_band(source, scene_name, layer_name, issues)
        band = source[:band]&.to_sym
        return if FREQUENCY_BANDS.include?(band)

        issues << error("scene #{scene_name} layer #{layer_name} uses unsupported frequency band: #{band.inspect}")
      end

      def validate_onset_band(source, scene_name, layer_name, issues)
        return unless source.key?(:band)

        band = source[:band]&.to_sym
        return if FREQUENCY_BANDS.include?(band)

        issues << error("scene #{scene_name} layer #{layer_name} uses unsupported onset band: #{band.inspect}")
      end

      def validate_transform(transform, scene_name, layer_name, target, issues)
        return unless transform.key?(:min) && transform.key?(:max)
        return unless Float(transform[:min]) > Float(transform[:max])

        issues << error("scene #{scene_name} layer #{layer_name} mapping #{target} has min greater than max")
      rescue ArgumentError, TypeError
        issues << error("scene #{scene_name} layer #{layer_name} mapping #{target} has non-numeric min/max")
      end

      def validate_transitions(transitions, names, issues)
        transitions.each do |transition|
          from = transition[:from]&.to_sym
          to = transition[:to]&.to_sym
          issues << error("transition has unknown source scene: #{from}") if from && !names.include?(from)
          issues << error("transition has unknown target scene: #{to}") if to && !names.include?(to)
          unless transition[:trigger].respond_to?(:call)
            issues << warn("transition #{from || '?'} -> #{to || '?'} has no trigger block")
          end
        end
      end

      def validate_key_mappings(mappings, names, issues)
        mappings.each do |mapping|
          key = mapping[:key] || mapping["key"]
          action = mapping[:action] || mapping["action"]
          issues << error("key mapping has empty key") if key.to_s.strip.empty?
          validate_key_action(action.is_a?(Hash) ? action : {}, names, key, issues)
        end
      end

      def validate_key_action(action, names, key, issues)
        type = (action[:type] || action["type"]).to_s.to_sym
        case type
        when :switch_scene
          scene = action[:scene] || action["scene"]
          scene_name = scene&.to_sym
          issues << error("key #{key} switches to unknown scene: #{scene}") unless scene_name && names.include?(scene_name)
        when :live_control
          control = (action[:control] || action["control"]).to_s.to_sym
          issues << error("key #{key} uses unsupported live control: #{control}") unless %i[blackout freeze].include?(control)
        else
          issues << error("key #{key} has unsupported action: #{type}")
        end
      end

      def scene_names(scenes)
        scenes.filter_map { |scene| scene[:name]&.to_sym }.to_set
      end

      def duplicate_values(values)
        counts = Hash.new(0)
        values.each { |value| counts[value] += 1 }
        counts.select { |_value, count| count > 1 }.keys
      end

      def error(message)
        Issue.new(severity: :error, message: message)
      end

      def warn(message)
        Issue.new(severity: :warn, message: message)
      end
    end
  end
end
