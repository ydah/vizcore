# frozen_string_literal: true

require_relative "mapping_transform_builder"
require_relative "reaction_builder"

module Vizcore
  module DSL
    # Builder for one render layer in a scene.
    class LayerBuilder
      # @param name [Symbol, String] layer identifier
      # @param styles [Hash] reusable layer parameter styles
      # @param defaults [Hash] default params applied before layer-specific values
      def initialize(name:, styles: {}, defaults: {})
        @name = name.to_sym
        @styles = styles
        @type = nil
        @shader = nil
        @glsl = nil
        @params = deep_dup(defaults)
        @param_schema = {}
        @mappings = []
      end

      # Evaluate a layer block.
      #
      # @yield Layer DSL methods
      # @return [Vizcore::DSL::LayerBuilder]
      def evaluate(&block)
        instance_eval(&block) if block
        self
      end

      # @param value [Symbol, String] layer type (`shader`, `particle_field`, etc.)
      # @return [Symbol]
      def type(value)
        @type = value.to_sym
      end

      # @param value [Symbol, String] built-in shader key or custom GLSL path
      # @param reload [Boolean, nil] accepted for custom shader path compatibility
      # @return [Symbol]
      def shader(value, reload: nil)
        if shader_path?(value)
          @glsl = value.to_s
          @params[:shader_reload] = !!reload unless reload.nil?
        else
          @shader = value.to_sym
        end
        @type ||= :shader
      end

      # @param path [String, Pathname] custom fragment shader path
      # @return [String]
      def glsl(path)
        @glsl = path.to_s
        @type ||= :shader
      end

      # @param value [Integer] particle count or similar numeric parameter
      # @return [Integer]
      def count(value)
        @params[:count] = Integer(value)
      end

      # @param value [String] text content
      # @return [String]
      def content(value)
        @params[:content] = value.to_s
      end

      # @param value [Integer] font size in pixels
      # @return [Integer]
      def font_size(value)
        @params[:font_size] = Integer(value)
      end

      # @param value [Symbol, String] text alignment (`left`, `center`, `right`)
      # @return [Symbol]
      def align(value)
        alignment = value.to_sym
        raise ArgumentError, "unsupported text align: #{value.inspect}" unless %i[left center right].include?(alignment)

        @params[:align] = alignment
      end

      # @param value [String] text font family
      # @return [String]
      def font(value)
        @params[:font] = value.to_s
      end

      # @param value [String] text fill color
      # @return [String]
      def fill(value)
        @params[:color] = value.to_s
      end

      # @param width [Numeric, nil] text stroke width in pixels
      # @param color [String, nil] text stroke color
      # @return [Hash]
      def stroke(width: nil, color: nil)
        @params[:stroke_width] = normalize_non_negative_param_number(width, :stroke_width) unless width.nil?
        @params[:stroke_color] = color.to_s unless color.nil?
        @params
      end

      # @param color [String, nil] text shadow color
      # @param blur [Numeric, nil] text shadow blur in pixels
      # @return [Hash]
      def shadow(color: nil, blur: nil)
        @params[:shadow_color] = color.to_s unless color.nil?
        @params[:shadow_blur] = normalize_non_negative_param_number(blur, :shadow_blur) unless blur.nil?
        @params
      end

      # @param value [Symbol, String] layer compositing mode
      # @return [Symbol]
      def blend(value)
        @params[:blend] = value.to_sym
      end

      # Apply a named style by merging its params into this layer.
      #
      # @param name [Symbol, String] style identifier
      # @raise [ArgumentError] when the style is unknown
      # @return [Hash] applied style params
      def use_style(name)
        style_name = name.to_sym
        style_params = @styles.fetch(style_name) { raise ArgumentError, "unknown style: #{style_name}" }
        @params.merge!(deep_dup(style_params))
      end

      # Declare numeric metadata for a shader/layer parameter.
      #
      # @param name [Symbol, String] parameter name exposed as `u_param_<name>` for shaders
      # @param default [Numeric, nil] default value stored in layer params
      # @param range [Range, Array, nil] allowed numeric range
      # @param min [Numeric, nil] allowed minimum when `range` is not used
      # @param max [Numeric, nil] allowed maximum when `range` is not used
      # @param step [Numeric, nil] preferred UI step
      # @return [Hash]
      def param(name, default: nil, range: nil, min: nil, max: nil, step: nil)
        key = normalize_param_name(name)
        range_min, range_max = normalize_range(range, context: "param")
        min = range_min if min.nil?
        max = range_max if max.nil?

        metadata = { name: key }
        metadata[:default] = normalize_param_number(default, :default) unless default.nil?
        metadata[:min] = normalize_param_number(min, :min) unless min.nil?
        metadata[:max] = normalize_param_number(max, :max) unless max.nil?
        metadata[:step] = normalize_param_number(step, :step) unless step.nil?
        validate_param_range!(metadata)

        @params[key] = metadata[:default] if metadata.key?(:default)
        @param_schema[key] = metadata
      end

      # Map analysis source(s) to layer parameter target(s).
      #
      # @param definition [Hash, Symbol, String] mapping pairs or a single source
      # @raise [ArgumentError] when the mapping is empty or invalid
      # @return [void]
      def map(definition = nil, **options, &block)
        if options.key?(:to)
          transform_options = options.dup
          to = transform_options.delete(:to)
          transform_options = evaluate_transform_block(transform_options, &block) if block
          @mappings << build_mapping(
            source: normalize_source(definition),
            target: to,
            transform: normalize_transform(**transform_options)
          )
          return
        end

        mapping = definition.nil? ? options : Hash(definition)
        raise ArgumentError, "map requires at least one mapping pair" if mapping.empty?
        raise ArgumentError, "map block syntax supports one mapping pair" if block && mapping.length != 1

        mapping.each do |source, target|
          target_name, transform = normalize_target(target)
          transform = normalize_transform(**evaluate_transform_block(transform, &block)) if block
          @mappings << build_mapping(source: normalize_source(source), target: target_name, transform: transform)
        end
      end

      # High-level mapping DSL for describing audio reactions inside a layer.
      #
      # @param source_value [Hash, Symbol, String] analysis source descriptor
      # @yield Reaction block with `change` and `trigger`
      # @raise [ArgumentError] when no reaction block is provided
      # @return [void]
      def react_to(source_value, &block)
        raise ArgumentError, "react_to requires a block" unless block

        source_descriptor = normalize_source(source_value)
        reaction = ReactionBuilder.new(
          mapping_factory: lambda do |target, transform_options|
            build_mapping(
              source: source_descriptor,
              target: target,
              transform: normalize_transform(**transform_options)
            )
          end
        )
        @mappings.concat(reaction.evaluate(&block))
      end

      # @return [Hash] source descriptor for overall amplitude
      def amplitude
        source(:amplitude)
      end

      # @param name [Symbol, String] band key (`sub`, `low`, `mid`, `high`)
      # @return [Hash] source descriptor for a frequency band
      def frequency_band(name)
        source(:frequency_band, band: name.to_sym)
      end

      # @return [Hash] source descriptor for the sub-bass frequency band
      def sub
        frequency_band(:sub)
      end

      # @return [Hash] source descriptor for the low/bass frequency band
      def low
        frequency_band(:low)
      end

      # @return [Hash] source descriptor for the low/bass frequency band
      def bass
        frequency_band(:low)
      end

      # @return [Hash] source descriptor for the mid frequency band
      def mid
        frequency_band(:mid)
      end

      # @return [Hash] source descriptor for the high frequency band
      def high
        frequency_band(:high)
      end

      # @return [Hash] source descriptor for the high/treble frequency band
      def treble
        frequency_band(:high)
      end

      # @return [Hash] source descriptor for FFT spectrum array
      def fft_spectrum
        source(:fft_spectrum)
      end

      # @param band [Symbol, String, nil] optional band-specific onset key
      # @return [Hash] source descriptor for positive audio feature changes
      def onset(band = nil)
        options = band.nil? ? {} : { band: band.to_sym }
        source(:onset, **options)
      end

      # @return [Hash] source descriptor for low-band percussive confidence
      def kick
        source(:kick)
      end

      # @return [Hash] source descriptor for mid-band percussive confidence
      def snare
        source(:snare)
      end

      # @return [Hash] source descriptor for high-band percussive confidence
      def hihat
        source(:hihat)
      end

      # @return [Hash] source descriptor for beat trigger
      def beat?
        source(:beat)
      end

      # @return [Hash] source descriptor for beat trigger
      def beat
        beat?
      end

      # @return [Hash] source descriptor for beat detector confidence
      def beat_confidence
        source(:beat_confidence)
      end

      # @return [Hash] source descriptor for beat pulse decay value
      def beat_pulse
        source(:beat_pulse)
      end

      # @return [Hash] source descriptor for beat counter
      def beat_count
        source(:beat_count)
      end

      # @return [Hash] source descriptor for estimated BPM
      def bpm
        source(:bpm)
      end

      # @return [Hash] serialized layer payload
      def to_h
        layer = {
          name: @name,
          type: resolved_type,
          params: @params.dup
        }
        layer[:shader] = @shader if @shader
        layer[:glsl] = @glsl if @glsl
        layer[:param_schema] = @param_schema.values.map(&:dup) unless @param_schema.empty?
        layer[:mappings] = @mappings.map { |mapping| mapping.dup } unless @mappings.empty?
        layer
      end

      # Stores dynamic one-argument setters into `params`.
      # @api private
      def method_missing(method_name, *args, &block)
        if block.nil? && args.length == 1
          @params[method_name.to_sym] = args.first
          return args.first
        end

        super
      end

      def respond_to_missing?(method_name, include_private = false)
        @params.key?(method_name.to_sym) || super
      end

      private

      def resolved_type
        return @type if @type
        return :shader if @shader || @glsl

        :geometry
      end

      def shader_path?(value)
        return false if value.is_a?(Symbol)

        path = value.to_s
        %w[.frag .glsl].include?(File.extname(path).downcase) || path.include?("/")
      end

      def normalize_source(source_value)
        case source_value
        when Hash
          kind = source_value[:kind] || source_value["kind"]
          raise ArgumentError, "mapping source hash must contain :kind" unless kind

          source(kind.to_sym, **normalize_source_options(source_value))
        when Symbol
          source(source_value)
        when String
          source(source_value.to_sym)
        else
          raise ArgumentError, "unsupported mapping source: #{source_value.inspect}"
        end
      end

      def normalize_source_options(source_value)
        source_value.each_with_object({}) do |(key, value), options|
          symbol_key = key.to_sym
          next if symbol_key == :kind

          options[symbol_key] = value.respond_to?(:to_sym) ? value.to_sym : value
        end
      end

      def normalize_target(target)
        return [target.to_sym, {}] unless target.is_a?(Hash)

        values = target.each_with_object({}) { |(key, value), output| output[key.to_sym] = value }
        to = values.delete(:to)
        raise ArgumentError, "mapping target hash must contain :to" unless to

        [to.to_sym, normalize_transform(**values)]
      end

      def build_mapping(source:, target:, transform: {})
        output = { source: source, target: target.to_sym }
        output[:transform] = transform unless transform.empty?
        output
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

      def evaluate_transform_block(initial_options, &block)
        MappingTransformBuilder.new(initial_options).evaluate(&block).to_h
      end

      def normalize_param_name(name)
        key = name.to_s.strip
        raise ArgumentError, "param name is required" if key.empty?

        key.to_sym
      end

      def normalize_param_number(value, name)
        Float(value)
      rescue ArgumentError, TypeError
        raise ArgumentError, "param #{name} must be numeric"
      end

      def validate_param_range!(metadata)
        return unless metadata.key?(:min) && metadata.key?(:max)
        return if metadata[:min] <= metadata[:max]

        raise ArgumentError, "param min must be less than or equal to max"
      end

      def normalize_transform(gain: nil, range: nil, min: nil, max: nil, curve: nil, attack: nil, release: nil, deadzone: nil)
        range_min, range_max = normalize_range(range, context: "mapping")
        min = range_min if min.nil?
        max = range_max if max.nil?

        output = {}
        output[:deadzone] = normalize_non_negative_float(deadzone, :deadzone) unless deadzone.nil?
        output[:gain] = normalize_float(gain, :gain) unless gain.nil?
        output[:min] = normalize_float(min, :min) unless min.nil?
        output[:max] = normalize_float(max, :max) unless max.nil?
        output[:curve] = normalize_curve(curve) unless curve.nil?
        output[:attack] = clamp(normalize_float(attack, :attack), 0.0, 1.0) unless attack.nil?
        output[:release] = clamp(normalize_float(release, :release), 0.0, 1.0) unless release.nil?
        output
      end

      def normalize_range(value, context:)
        return [nil, nil] if value.nil?

        if value.is_a?(Range)
          return [value.begin, value.end]
        end

        if value.is_a?(Array) && value.length == 2
          return value
        end

        raise ArgumentError, "#{context} range must be a Range or two-element Array"
      end

      def normalize_float(value, name)
        Float(value)
      rescue ArgumentError, TypeError
        raise ArgumentError, "mapping #{name} must be numeric"
      end

      def normalize_non_negative_float(value, name)
        numeric = normalize_float(value, name)
        raise ArgumentError, "mapping #{name} must be non-negative" if numeric.negative?

        numeric
      end

      def normalize_non_negative_param_number(value, name)
        numeric = Float(value)
        raise ArgumentError, "#{name} must be non-negative" if numeric.negative?

        numeric
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{name} must be numeric"
      end

      def normalize_curve(value)
        curve = value.to_sym
        return curve if %i[linear sqrt square ease_out].include?(curve)

        raise ArgumentError, "unsupported mapping curve: #{value.inspect}"
      end

      def clamp(value, min, max)
        [[value, min].max, max].min
      end

      def source(kind, **options)
        {
          kind: kind.to_sym,
          **options
        }
      end
    end
  end
end
