# frozen_string_literal: true

require_relative "mapping_transform_builder"
require_relative "reaction_builder"
require_relative "../shape"

module Vizcore
  module DSL
    # Builder for one render layer in a scene.
    class LayerBuilder
      NO_ARGUMENT = Object.new.freeze
      SHAPE_SCHEMA_VERSION = 2
      MAPPING_SOURCE_KINDS = %i[
        amplitude frequency_band fft_spectrum onset kick snare hihat beat beat_confidence beat_pulse beat_count bpm
      ].freeze
      PATH_DEFAULT_DETAIL = 32
      PATH_MIN_DETAIL = 4
      PATH_MAX_DETAIL = 128
      PATH_DEFAULT_MAX_SEGMENTS = 4096
      SHAPE_TARGET_ALIASES = {
        "translate_x" => "transform.translate.x",
        "translate_y" => "transform.translate.y",
        "rotate" => "transform.rotate",
        "rotation" => "transform.rotate",
        "scale" => "transform.scale",
        "scale_x" => "transform.scale.x",
        "scale_y" => "transform.scale.y",
        "origin_x" => "transform.origin.x",
        "origin_y" => "transform.origin.y"
      }.freeze
      SHAPE_STYLE_KEYS = Vizcore::Shape::STYLE_KEYS
      SHAPE_TRANSFORM_KEYS = %i[translate rotate rotation scale origin].freeze

      # Reference to an already declared shape, used by `map ... to: shape(:id).radius`.
      class ShapeReference
        def initialize(prefix)
          @prefix = prefix
        end

        def method_missing(method_name, *args, &block)
          return super unless args.empty? && block.nil?

          target = SHAPE_TARGET_ALIASES.fetch(method_name.to_s, method_name.to_s)
          :"#{@prefix}.#{target}"
        end

        def respond_to_missing?(_method_name, _include_private = false)
          true
        end
      end

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
        @shape_index_by_id = {}
        @shape_group_stack = [{}]
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

      # @param path [String, Pathname] asset file path used by media-like layers
      # @return [String]
      def file(path)
        @params[:file] = path.to_s
      end

      # Declare a 2D circle/ring primitive for a shape layer.
      #
      # @param options [Hash] shape params such as `count`, `radius`, `x`, and `y`
      # @yield optional block evaluated in the shape context
      # @return [Hash]
      def circle(id = nil, **options, &block)
        build_shape(:circle, shape_options(id, options), &block)
      end

      # Declare a 2D line primitive for a shape layer.
      #
      # @param options [Hash] shape params such as `x1`, `y1`, `x2`, and `y2`
      # @yield optional block evaluated in the shape context
      # @return [Hash]
      def line(id = nil, **options, &block)
        build_shape(:line, shape_options(id, options), &block)
      end

      # Declare a 2D rectangle primitive for a shape layer.
      #
      # @param id [Symbol, String, nil] optional shape identifier
      # @param options [Hash] shape params such as `x`, `y`, `width`, `height`, and `radius`
      # @yield optional block evaluated in the shape context
      # @return [Hash]
      def rect(id = nil, **options, &block)
        build_shape(:rect, shape_options(id, options), schema_version: true, &block)
      end

      # Declare a closed polygon primitive for a shape layer.
      #
      # @param id [Symbol, String, nil] optional shape identifier
      # @param options [Hash] shape params including `points`
      # @yield optional block evaluated in the shape context
      # @return [Hash]
      def polygon(id = nil, **options, &block)
        build_shape(:polygon, shape_options(id, options), schema_version: true, &block)
      end

      # Declare an open polyline primitive for a shape layer.
      #
      # @param id [Symbol, String, nil] optional shape identifier
      # @param options [Hash] shape params including `points`
      # @yield optional block evaluated in the shape context
      # @return [Hash]
      def polyline(id = nil, **options, &block)
        build_shape(:polyline, shape_options(id, options).merge(closed: false), schema_version: true, &block)
      end

      # Declare a path primitive using SVG-like path commands.
      #
      # @param id [Symbol, String, nil] optional shape identifier
      # @param options [Hash] path params such as `detail`
      # @yield block containing path commands and shape styling
      # @return [Hash]
      def path(id = nil, **options, &block)
        shape = shape_options(id, options)
        shape[:commands] ||= []
        build_shape(:path, shape, schema_version: true, &block)
      end

      # Declare a quadratic or cubic bezier curve. The serialized primitive is a path.
      #
      # @param id [Symbol, String, nil] optional shape identifier
      # @param from [Array<Numeric>] start point
      # @param to [Array<Numeric>] end point
      # @param control [Array<Numeric>, nil] quadratic control point
      # @param c1 [Array<Numeric>, nil] first cubic control point
      # @param c2 [Array<Numeric>, nil] second cubic control point
      # @param options [Hash] additional path params
      # @yield optional block evaluated in the shape context
      # @return [Hash]
      def bezier(id = nil, from:, to:, control: nil, c1: nil, c2: nil, **options, &block)
        commands = [["M", *point_values(from)]]
        if control
          commands << ["Q", *point_values(control), *point_values(to)]
        elsif c1 && c2
          commands << ["C", *point_values(c1), *point_values(c2), *point_values(to)]
        else
          raise ArgumentError, "bezier requires either :control or both :c1 and :c2"
        end

        build_shape(:path, shape_options(id, options).merge(commands: commands), schema_version: true, &block)
      end

      # Declare a star polygon primitive for a shape layer.
      #
      # @param id [Symbol, String, nil] optional shape identifier
      # @param options [Hash] shape params such as `points`, `radius`, and `inner_radius`
      # @yield optional block evaluated in the shape context
      # @return [Hash]
      def star(id = nil, **options, &block)
        build_shape(:star, shape_options(id, options), schema_version: true, &block)
      end

      # Expand a registered Ruby custom shape into normal shape primitives.
      #
      # @param renderer [Symbol, String, Class, Module, #call] registered shape name or renderer
      # @param options [Hash] custom shape params
      # @yield optional block applied to each generated primitive
      # @return [Array<Hash>]
      def custom_shape(renderer, **options, &block)
        mark_shape_schema_version!
        shape_id = options.delete(:id)
        dynamic = options.delete(:dynamic)
        static = options.delete(:static)
        raise ArgumentError, "custom_shape cannot be both static and dynamic" if dynamic && static

        dynamic = true if static == false
        return append_dynamic_custom_shape(renderer, options, shape_id: shape_id, &block) if dynamic

        primitives = expand_custom_shape(renderer, options, shape_id: shape_id)
        raise ArgumentError, "custom_shape produced no primitives" if primitives.empty?
        raise ArgumentError, "custom_shape id can only be assigned when one primitive is produced" if shape_id && primitives.length > 1

        @type ||= :shape
        @params[:shapes] ||= []
        primitives.map do |primitive|
          primitive[:id] ||= shape_id.to_sym if shape_id
          append_expanded_shape(primitive, &block)
        end
      end

      # Apply shared style and transform to shape primitives declared in the block.
      #
      # Group attributes are flattened into child primitives so the frontend only
      # needs to render regular shape primitives.
      #
      # @param id [Symbol, String, nil] optional group identifier, currently documentation-only
      # @param attrs [Hash] initial group style/transform attrs
      # @yield shape declarations
      # @return [Array<Hash>]
      def group(_id = nil, **attrs, &block)
        raise ArgumentError, "group requires a block" unless block

        mark_shape_schema_version!
        @type ||= :shape
        @shape_group_stack << merge_shape_group(current_shape_group, normalize_shape_group(attrs))
        instance_eval(&block)
        @params[:shapes] || []
      ensure
        @shape_group_stack.pop if @shape_group_stack.length > 1
      end

      # Group shape primitives in a block for readability.
      #
      # @yield shape declarations
      # @return [Array<Hash>]
      def draw(&block)
        @type ||= :shape
        instance_eval(&block) if block
        @params[:shapes] || []
      end

      # @param value [Symbol, String] input source for media-like layers
      # @return [Symbol, Hash]
      def source(value, **options)
        source_name = value.to_sym
        return mapping_source(source_name, **options) if options.any? || MAPPING_SOURCE_KINDS.include?(source_name)

        @params[:source] = source_name
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

      # @param value [Numeric] extra spacing between text glyphs in pixels
      # @return [Float]
      def letter_spacing(value)
        @params[:letter_spacing] = normalize_non_negative_param_number(value, :letter_spacing)
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
        if @current_shape
          @current_shape[:fill] = value.to_s
          mark_shape_schema_version!
          return @current_shape
        end

        if @current_custom_shape
          current_custom_shape_style[:fill] = value.to_s
          return @current_custom_shape
        end

        if in_shape_group?
          current_shape_group[:fill] = value.to_s
          return current_shape_group
        end

        @params[:color] = value.to_s
      end

      # @param width [Numeric, nil] text stroke width in pixels
      # @param color [String, nil] text stroke color
      # @return [Hash]
      def stroke(value = NO_ARGUMENT, width: nil, color: nil)
        if @current_shape
          @current_shape[:stroke] = normalize_non_negative_param_number(value, :stroke) unless value.equal?(NO_ARGUMENT)
          @current_shape[:stroke_width] = normalize_non_negative_param_number(width, :stroke_width) unless width.nil?
          @current_shape[:stroke_color] = color.to_s unless color.nil?
          return @current_shape
        end

        if @current_custom_shape
          current_custom_shape_style[:stroke] = normalize_non_negative_param_number(value, :stroke) unless value.equal?(NO_ARGUMENT)
          current_custom_shape_style[:stroke_width] = normalize_non_negative_param_number(width, :stroke_width) unless width.nil?
          current_custom_shape_style[:stroke_color] = color.to_s unless color.nil?
          return @current_custom_shape
        end

        if in_shape_group?
          current_shape_group[:stroke] = normalize_non_negative_param_number(value, :stroke) unless value.equal?(NO_ARGUMENT)
          current_shape_group[:stroke_width] = normalize_non_negative_param_number(width, :stroke_width) unless width.nil?
          current_shape_group[:stroke_color] = color.to_s unless color.nil?
          return current_shape_group
        end

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
        if @current_shape
          @current_shape[:blend] = value.to_sym
          mark_shape_schema_version!
          return @current_shape
        end

        if @current_custom_shape
          current_custom_shape_style[:blend] = value.to_sym
          return @current_custom_shape
        end

        if in_shape_group?
          current_shape_group[:blend] = value.to_sym
          return current_shape_group
        end

        @params[:blend] = value.to_sym
      end

      # Set layer or shape opacity.
      #
      # @param value [Numeric]
      # @return [Float, Hash]
      def opacity(value)
        if @current_shape
          @current_shape[:opacity] = normalize_param_number(value, :opacity)
          mark_shape_schema_version!
          return @current_shape
        end

        if @current_custom_shape
          current_custom_shape_style[:opacity] = normalize_param_number(value, :opacity)
          return @current_custom_shape
        end

        if in_shape_group?
          current_shape_group[:opacity] = current_shape_group.key?(:opacity) ? normalize_param_number(current_shape_group[:opacity], :opacity) * normalize_param_number(value, :opacity) : normalize_param_number(value, :opacity)
          return current_shape_group
        end

        @params[:opacity] = normalize_param_number(value, :opacity)
      end

      # Set a shape/layer translation transform.
      #
      # @param args [Array<Numeric>]
      # @param x [Numeric, nil]
      # @param y [Numeric, nil]
      # @return [Hash]
      def translate(*args, x: nil, y: nil)
        values = normalize_xy_args(args, x: x, y: y, name: :translate)
        if @current_shape
          current_shape_transform[:translate] = values
          return @current_shape
        end

        if @current_custom_shape
          current_custom_shape_transform[:translate] = add_shape_xy(current_custom_shape_transform[:translate], values)
          return @current_custom_shape
        end

        if in_shape_group?
          current_shape_group_transform[:translate] = add_shape_xy(current_shape_group_transform[:translate], values)
          return current_shape_group
        end

        @params[:translate] = values
      end

      # Set a shape/layer rotation transform in degrees.
      #
      # @param value [Numeric]
      # @return [Float, Hash]
      def rotate(value)
        rotation = normalize_param_number(value, :rotate)
        if @current_shape
          current_shape_transform[:rotate] = rotation
          return @current_shape
        end

        if @current_custom_shape
          current_custom_shape_transform[:rotate] = normalize_param_number(current_custom_shape_transform[:rotate] || 0, :rotate) + rotation
          return @current_custom_shape
        end

        if in_shape_group?
          current_shape_group_transform[:rotate] = normalize_param_number(current_shape_group_transform[:rotate] || 0, :rotate) + rotation
          return current_shape_group
        end

        @params[:rotate] = rotation
      end

      # Set a shape/layer scale transform.
      #
      # @param value [Numeric]
      # @param x [Numeric, nil]
      # @param y [Numeric, nil]
      # @return [Float, Hash]
      def scale(value = NO_ARGUMENT, x: nil, y: nil)
        scale_value = normalize_scale_args(value, x: x, y: y)
        if @current_shape
          current_shape_transform[:scale] = scale_value
          return @current_shape
        end

        if @current_custom_shape
          current_custom_shape_transform[:scale] = multiply_shape_scale(current_custom_shape_transform[:scale], scale_value)
          return @current_custom_shape
        end

        if in_shape_group?
          current_shape_group_transform[:scale] = multiply_shape_scale(current_shape_group_transform[:scale], scale_value)
          return current_shape_group
        end

        @params[:scale] = scale_value
      end

      # Set a shape/layer transform origin.
      #
      # @param args [Array<Numeric>]
      # @param x [Numeric, nil]
      # @param y [Numeric, nil]
      # @return [Hash]
      def origin(*args, x: nil, y: nil)
        values = normalize_xy_args(args, x: x, y: y, name: :origin)
        if @current_shape
          current_shape_transform[:origin] = values
          return @current_shape
        end

        if @current_custom_shape
          current_custom_shape_transform[:origin] = values
          return @current_custom_shape
        end

        if in_shape_group?
          current_shape_group_transform[:origin] = values
          return current_shape_group
        end

        @params[:origin] = values
      end

      # Return a reference object for mapping to a named shape.
      #
      # @param id [Symbol, String]
      # @return [ShapeReference]
      def shape(id)
        key = id.to_sym
        index = @shape_index_by_id.fetch(key) { raise ArgumentError, "unknown shape id: #{key.inspect}" }
        ShapeReference.new("shapes.#{index}")
      end

      def move_to(x, y)
        append_path_command("M", x, y)
      end

      def line_to(x, y)
        append_path_command("L", x, y)
      end

      def quad_to(cx, cy, x, y)
        append_path_command("Q", cx, cy, x, y)
      end

      def cubic_to(c1x, c1y, c2x, c2y, x, y)
        append_path_command("C", c1x, c1y, c2x, c2y, x, y)
      end

      def horizontal_to(x)
        append_path_command("H", x)
      end

      def vertical_to(y)
        append_path_command("V", y)
      end

      def arc_to(rx, ry, rotation, large_arc, sweep, x, y)
        append_path_command("A", rx, ry, rotation, large_arc, sweep, x, y)
      end

      def close
        append_path_command("Z")
      end

      # Store an ordered color palette for this layer.
      #
      # @param colors [Array<String, Array<String>>] color values such as "#00ffff"
      # @raise [ArgumentError] when no non-blank colors are supplied
      # @return [Array<String>]
      def palette(*colors)
        @params[:palette] = normalize_palette(colors)
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
        definition, options = normalize_custom_shape_mapping(definition, options) if @custom_shape_target_prefix
        definition, options = normalize_shape_mapping(definition, options) if @shape_target_prefix

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
        mapping_source(:amplitude)
      end

      # @param name [Symbol, String] band key (`sub`, `low`, `mid`, `high`)
      # @return [Hash] source descriptor for a frequency band
      def frequency_band(name)
        mapping_source(:frequency_band, band: name.to_sym)
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
        mapping_source(:fft_spectrum)
      end

      # @param band [Symbol, String, nil] optional band-specific onset key
      # @return [Hash] source descriptor for positive audio feature changes
      def onset(band = nil)
        options = band.nil? ? {} : { band: band.to_sym }
        mapping_source(:onset, **options)
      end

      # @return [Hash] source descriptor for low-band percussive confidence
      def kick(value = NO_ARGUMENT)
        return @params[:kick] = value unless value.equal?(NO_ARGUMENT)

        mapping_source(:kick)
      end

      # @return [Hash] source descriptor for mid-band percussive confidence
      def snare(value = NO_ARGUMENT)
        return @params[:snare] = value unless value.equal?(NO_ARGUMENT)

        mapping_source(:snare)
      end

      # @return [Hash] source descriptor for high-band percussive confidence
      def hihat(value = NO_ARGUMENT)
        return @params[:hihat] = value unless value.equal?(NO_ARGUMENT)

        mapping_source(:hihat)
      end

      # @return [Hash] source descriptor for beat trigger
      def beat?
        mapping_source(:beat)
      end

      # @return [Hash] source descriptor for beat trigger
      def beat
        beat?
      end

      # @return [Hash] source descriptor for beat detector confidence
      def beat_confidence
        mapping_source(:beat_confidence)
      end

      # @return [Hash] source descriptor for beat pulse decay value
      def beat_pulse
        mapping_source(:beat_pulse)
      end

      # @return [Hash] source descriptor for beat counter
      def beat_count
        mapping_source(:beat_count)
      end

      # @return [Hash] source descriptor for estimated BPM
      def bpm
        mapping_source(:bpm)
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
        if @current_shape && block.nil? && args.length == 1
          @current_shape[method_name.to_sym] = args.first
          return args.first
        end

        if @current_custom_shape && block.nil? && args.length == 1
          @current_custom_shape[:params][method_name.to_sym] = args.first
          return args.first
        end

        if in_shape_group? && block.nil? && args.length == 1
          current_shape_group[method_name.to_sym] = args.first
          return args.first
        end

        if block.nil? && args.length == 1
          @params[method_name.to_sym] = args.first
          return args.first
        end

        super
      end

      def respond_to_missing?(method_name, include_private = false)
        !!@current_custom_shape || @params.key?(method_name.to_sym) || super
      end

      private

      def build_shape(kind, options, schema_version: false, &block)
        @type ||= :shape
        mark_shape_schema_version! if schema_version
        shape = normalize_shape(kind, options)
        @params[:shapes] ||= []
        shape_index = @params[:shapes].length
        register_shape_id!(shape, shape_index)
        @params[:shapes] << shape

        with_shape_context(shape, shape_index) do
          instance_eval(&block) if block
        end
        apply_current_shape_group!(shape)
        validate_shape!(shape)

        shape
      end

      def append_expanded_shape(shape, &block)
        shape_index = @params[:shapes].length
        register_shape_id!(shape, shape_index)
        @params[:shapes] << shape

        with_shape_context(shape, shape_index) do
          instance_eval(&block) if block
        end
        apply_current_shape_group!(shape)
        validate_shape!(shape)

        shape
      end

      def append_dynamic_custom_shape(renderer, options, shape_id:, &block)
        definition = custom_shape_definition(renderer)
        @type ||= :shape
        @params[:custom_shapes] ||= []
        descriptor = {
          name: definition.name || renderer,
          renderer: definition.renderer,
          params: deep_dup(options),
          style: {},
          transform: {},
          dynamic: true
        }
        descriptor[:shape_id] = shape_id.to_sym if shape_id
        descriptor_index = @params[:custom_shapes].length
        @params[:custom_shapes] << descriptor

        with_custom_shape_context(descriptor, descriptor_index) do
          instance_eval(&block) if block
        end
        apply_current_shape_group_to_custom_shape!(descriptor)

        descriptor
      end

      def shape_options(id, options)
        return options if id.nil?

        raise ArgumentError, "shape id specified twice" if options.key?(:id)

        options.merge(id: id.to_sym)
      end

      def normalize_shape(kind, options)
        shape = { kind: kind.to_sym }
        options.each do |key, value|
          shape[key.to_sym] = value
        end
        shape
      end

      def normalize_shape_group(attrs)
        attrs.each_with_object({}) do |(key, value), group|
          symbol_key = key.to_sym
          if SHAPE_TRANSFORM_KEYS.include?(symbol_key)
            transform_key = symbol_key == :rotation ? :rotate : symbol_key
            group[:transform] ||= {}
            group[:transform][transform_key] = value
          else
            group[symbol_key] = value
          end
        end
      end

      def merge_shape_group(parent, child)
        output = deep_dup(parent)
        child.each do |key, value|
          if key == :transform
            output[:transform] = compose_shape_transform(output[:transform], value)
          elsif key == :opacity && output.key?(:opacity)
            output[:opacity] = normalize_param_number(output[:opacity], :opacity) * normalize_param_number(value, :opacity)
          else
            output[key] = deep_dup(value)
          end
        end
        output
      end

      def apply_current_shape_group!(shape)
        group = current_shape_group
        return shape if group.empty?

        SHAPE_STYLE_KEYS.each do |key|
          next unless group.key?(key)

          if key == :opacity && shape.key?(:opacity)
            shape[:opacity] = normalize_param_number(group[:opacity], :opacity) * normalize_param_number(shape[:opacity], :opacity)
          else
            shape[key] = deep_dup(group[key]) unless shape.key?(key)
          end
        end
        shape[:transform] = compose_shape_transform(group[:transform], shape[:transform]) if group[:transform]
        shape
      end

      def apply_current_shape_group_to_custom_shape!(descriptor)
        group = current_shape_group
        return descriptor if group.empty?

        style = descriptor[:style] ||= {}
        SHAPE_STYLE_KEYS.each do |key|
          next unless group.key?(key)

          if key == :opacity && style.key?(:opacity)
            style[:opacity] = normalize_param_number(group[:opacity], :opacity) * normalize_param_number(style[:opacity], :opacity)
          else
            style[key] = deep_dup(group[key]) unless style.key?(key)
          end
        end
        descriptor[:transform] = compose_shape_transform(group[:transform], descriptor[:transform]) if group[:transform]
        descriptor
      end

      def compose_shape_transform(parent, child)
        return deep_dup(child || {}) unless parent

        child ||= {}
        output = deep_dup(parent)
        output[:translate] = add_shape_xy(parent[:translate], child[:translate]) if child.key?(:translate)
        output[:origin] = child[:origin] if child.key?(:origin)
        output[:rotate] = normalize_param_number(parent[:rotate] || 0, :rotate) + normalize_param_number(child[:rotate] || 0, :rotate) if child.key?(:rotate)
        output[:scale] = multiply_shape_scale(parent[:scale], child[:scale]) if child.key?(:scale)
        output
      end

      def add_shape_xy(parent, child)
        parent ||= {}
        child ||= {}
        {
          x: normalize_param_number(parent[:x] || parent["x"] || 0, :"translate.x") + normalize_param_number(child[:x] || child["x"] || 0, :"translate.x"),
          y: normalize_param_number(parent[:y] || parent["y"] || 0, :"translate.y") + normalize_param_number(child[:y] || child["y"] || 0, :"translate.y")
        }
      end

      def multiply_shape_scale(parent, child)
        parent = shape_scale_pair(parent)
        child = shape_scale_pair(child)
        { x: parent[:x] * child[:x], y: parent[:y] * child[:y] }
      end

      def shape_scale_pair(value)
        return { x: normalize_param_number(value[:x] || value["x"] || 1, :"scale.x"), y: normalize_param_number(value[:y] || value["y"] || 1, :"scale.y") } if value.is_a?(Hash)

        scale = normalize_param_number(value || 1, :scale)
        { x: scale, y: scale }
      end

      def current_shape_group
        @shape_group_stack.last
      end

      def current_shape_group_transform
        current_shape_group[:transform] ||= {}
      end

      def current_custom_shape_style
        @current_custom_shape[:style] ||= {}
      end

      def current_custom_shape_transform
        @current_custom_shape[:transform] ||= {}
      end

      def in_shape_group?
        @shape_group_stack.length > 1
      end

      def validate_shape!(shape)
        validate_non_negative_shape_numbers!(shape)
        case shape.fetch(:kind)
        when :polygon
          validate_shape_points!(shape, minimum: 3)
        when :polyline
          validate_shape_points!(shape, minimum: 2)
        when :path
          validate_path_shape!(shape)
        end
      end

      def validate_path_shape!(shape)
        commands = Array(shape[:commands])
        raise ArgumentError, "Invalid path#{shape_label(shape)}: commands must not be empty" if commands.empty?

        detail = normalized_path_integer(shape, :detail, PATH_DEFAULT_DETAIL).clamp(PATH_MIN_DETAIL, PATH_MAX_DETAIL)
        max_segments = normalized_path_integer(shape, :max_segments, PATH_DEFAULT_MAX_SEGMENTS)
        validate_path_tolerance!(shape)

        segment_count = estimated_path_segments(commands, detail)
        return if segment_count <= max_segments

        raise ArgumentError,
              "Invalid path#{shape_label(shape)}: max_segments exceeded (#{segment_count} > #{max_segments})"
      end

      def normalized_path_integer(shape, key, default)
        value = shape.key?(key) ? shape[key] : default
        numeric = Integer(value)
        raise ArgumentError if numeric <= 0

        numeric
      rescue ArgumentError, TypeError
        raise ArgumentError, "Invalid path#{shape_label(shape)}: #{key} must be a positive integer"
      end

      def validate_path_tolerance!(shape)
        return unless shape.key?(:tolerance)

        value = normalize_param_number(shape[:tolerance], :tolerance)
        return unless value.negative?

        raise ArgumentError, "Invalid path#{shape_label(shape)}: tolerance must be non-negative"
      end

      def estimated_path_segments(commands, detail)
        current = false
        subpath_start = false
        commands.sum do |entry|
          command, *values = Array(entry)
          case command.to_s.upcase
          when "M"
            current = values.length >= 2
            subpath_start = current
            0
          when "L"
            current && values.length >= 2 ? 1 : 0
          when "H", "V"
            current && values.length >= 1 ? 1 : 0
          when "Q"
            current && values.length >= 4 ? detail : 0
          when "C"
            current && values.length >= 6 ? detail : 0
          when "A"
            current && values.length >= 7 ? detail : 0
          when "Z"
            current && subpath_start ? 1 : 0
          else
            0
          end
        end
      end

      def validate_non_negative_shape_numbers!(shape)
        %i[radius width height stroke_width inner_radius].each do |key|
          next unless shape.key?(key)

          value = normalize_param_number(shape[key], key)
          raise ArgumentError, "Invalid #{shape.fetch(:kind)}#{shape_label(shape)}: #{key} must be non-negative" if value.negative?
        end
      end

      def validate_shape_points!(shape, minimum:)
        points = Array(shape[:points])
        valid_points = points.count { |point| Array(point).length >= 2 }
        return if valid_points >= minimum

        raise ArgumentError, "Invalid #{shape.fetch(:kind)}#{shape_label(shape)}: points must contain at least #{minimum} points"
      end

      def shape_label(shape)
        shape[:id] ? " `#{shape[:id]}`" : ""
      end

      def expand_custom_shape(renderer, options, shape_id:)
        definition = custom_shape_definition(renderer)
        Vizcore::Shape.expand_custom_shape(
          definition.renderer,
          params: options,
          shape_id: shape_id,
          layer_name: @name,
          palette: Array(@params[:palette]),
          shape_name: definition.name || renderer
        )
      end

      def custom_shape_definition(renderer)
        return Vizcore::Shape::Definition.new(name: nil, renderer: renderer) unless renderer.is_a?(Symbol) || renderer.is_a?(String)

        Vizcore.resolve_shape(renderer) || raise(ArgumentError, "Unknown custom shape: #{renderer.inspect}. Register it with `Vizcore.register_shape #{renderer.inspect}, ShapeClass`.")
      end

      def register_shape_id!(shape, shape_index)
        id = shape[:id]
        return if id.nil?

        key = id.to_sym
        raise ArgumentError, "duplicate shape id: #{key.inspect}" if @shape_index_by_id.key?(key)

        @shape_index_by_id[key] = shape_index
      end

      def current_shape_transform
        mark_shape_schema_version!
        @current_shape[:transform] ||= {}
      end

      def mark_shape_schema_version!
        @params[:shape_schema_version] ||= SHAPE_SCHEMA_VERSION
      end

      def normalize_xy_args(args, x:, y:, name:)
        if args.length == 2
          return { x: normalize_param_number(args[0], :"#{name}.x"), y: normalize_param_number(args[1], :"#{name}.y") }
        end

        if args.length == 1 && args.first.is_a?(Hash)
          values = args.first
          x = values.fetch(:x, values["x"])
          y = values.fetch(:y, values["y"])
        elsif args.any?
          raise ArgumentError, "#{name} expects x/y keywords or two numeric arguments"
        end

        {
          x: normalize_param_number(x || 0, :"#{name}.x"),
          y: normalize_param_number(y || 0, :"#{name}.y")
        }
      end

      def normalize_scale_args(value, x:, y:)
        if value.equal?(NO_ARGUMENT)
          return {
            x: normalize_param_number(x || 1, :"scale.x"),
            y: normalize_param_number(y || 1, :"scale.y")
          }
        end

        raise ArgumentError, "scale accepts either a value or x/y keywords" unless x.nil? && y.nil?

        normalize_param_number(value, :scale)
      end

      def append_path_command(command, *values)
        raise ArgumentError, "#{command} is only available inside a path shape" unless @current_shape&.fetch(:kind) == :path

        @current_shape[:commands] ||= []
        @current_shape[:commands] << [command, *values]
      end

      def point_values(value)
        values = Array(value)
        raise ArgumentError, "point must contain x and y" unless values.length == 2

        values
      end

      def with_shape_context(shape, shape_index)
        previous_shape = @current_shape
        previous_prefix = @shape_target_prefix
        @current_shape = shape
        @shape_target_prefix = "shapes.#{shape_index}"
        yield
      ensure
        @current_shape = previous_shape
        @shape_target_prefix = previous_prefix
      end

      def with_custom_shape_context(descriptor, descriptor_index)
        previous_custom_shape = @current_custom_shape
        previous_prefix = @custom_shape_target_prefix
        @current_custom_shape = descriptor
        @custom_shape_target_prefix = "custom_shapes.#{descriptor_index}"
        yield
      ensure
        @current_custom_shape = previous_custom_shape
        @custom_shape_target_prefix = previous_prefix
      end

      def normalize_custom_shape_mapping(definition, options)
        if options.key?(:to)
          prefixed_options = options.dup
          prefixed_options[:to] = prefixed_custom_shape_target(prefixed_options[:to])
          return [definition, prefixed_options]
        end

        mapping = definition.nil? ? options : Hash(definition)
        prefixed_mapping = mapping.each_with_object({}) do |(source, target), output|
          output[source] = prefix_custom_shape_target_value(target)
        end
        [prefixed_mapping, {}]
      end

      def prefix_custom_shape_target_value(target)
        return prefixed_custom_shape_target(target) unless target.is_a?(Hash)

        target.merge(to: prefixed_custom_shape_target(target.fetch(:to)))
      rescue KeyError
        target
      end

      def prefixed_custom_shape_target(target)
        target_name = target.to_s
        return :"#{@custom_shape_target_prefix}.#{target_name}" if target_name.match?(/\A(?:params|style|transform)\./)

        resolved_target = SHAPE_TARGET_ALIASES[target_name]
        return :"#{@custom_shape_target_prefix}.#{resolved_target}" if resolved_target
        return :"#{@custom_shape_target_prefix}.style.#{target_name}" if SHAPE_STYLE_KEYS.include?(target_name.to_sym)

        :"#{@custom_shape_target_prefix}.params.#{target_name}"
      end

      def normalize_shape_mapping(definition, options)
        if options.key?(:to)
          prefixed_options = options.dup
          prefixed_options[:to] = prefixed_shape_target(prefixed_options[:to])
          return [definition, prefixed_options]
        end

        mapping = definition.nil? ? options : Hash(definition)
        prefixed_mapping = mapping.each_with_object({}) do |(source, target), output|
          output[source] = prefix_shape_target_value(target)
        end
        [prefixed_mapping, {}]
      end

      def prefix_shape_target_value(target)
        return prefixed_shape_target(target) unless target.is_a?(Hash)

        target.merge(to: prefixed_shape_target(target.fetch(:to)))
      rescue KeyError
        target
      end

      def prefixed_shape_target(target)
        target_name = target.to_s
        resolved_target = SHAPE_TARGET_ALIASES.fetch(target_name, target_name)
        :"#{@shape_target_prefix}.#{resolved_target}"
      end

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

          mapping_source(kind.to_sym, **normalize_source_options(source_value))
        when Symbol
          mapping_source(source_value)
        when String
          mapping_source(source_value.to_sym)
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

      def normalize_palette(colors)
        values = colors.flatten.map { |color| color.to_s.strip }.reject(&:empty?)
        raise ArgumentError, "layer #{@name} palette requires at least one color" if values.empty?

        values
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

      def mapping_source(kind, **options)
        {
          kind: kind.to_sym,
          **options
        }
      end
    end
  end
end
