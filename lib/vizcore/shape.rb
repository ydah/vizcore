# frozen_string_literal: true

module Vizcore
  # Mixin and runtime helpers for Ruby-defined custom shape generators.
  module Shape
    SUPPORTED_PRIMITIVES = %i[circle line rect polygon polyline path star].freeze
    STYLE_KEYS = %i[fill stroke stroke_width stroke_color opacity blend line_cap line_join miter_limit dash].freeze
    Definition = Struct.new(:name, :renderer, keyword_init: true)

    class << self
      def included(base)
        base.extend(ClassMethods)
      end

      def normalize_primitives(value, shape_name:)
        primitives = case value
                     when nil
                       []
                     when Hash
                       [value]
                     else
                       Array(value)
                     end
        primitives.map { |primitive| normalize_primitive(primitive, shape_name: shape_name) }
      end

      def expand_custom_shape(renderer, params:, shape_id: nil, layer_name: nil, palette: [], audio: {}, time: 0.0, frame: 0, resolution: [1280, 720], globals: {}, shape_name: nil, cache: false)
        definition = shape_definition(renderer)
        renderer = definition.renderer if definition
        shape_name ||= definition&.name || renderer
        cache_key = custom_shape_cache_key(
          renderer: renderer,
          params: params,
          shape_id: shape_id,
          layer_name: layer_name,
          palette: palette,
          resolution: resolution,
          globals: globals,
          shape_name: shape_name
        ) if cache
        return deep_dup(custom_shape_cache[cache_key]) if cache_key && custom_shape_cache.key?(cache_key)

        context = DrawContext.new(
          params: params,
          param_schema: param_schema_for(renderer),
          shape_id: shape_id,
          layer_name: layer_name,
          palette: palette,
          audio: audio,
          time: time,
          frame: frame,
          resolution: resolution,
          globals: globals
        )
        result = call_renderer(renderer, context, params)
        result = context.shapes if result.nil?
        primitives = normalize_primitives(result, shape_name: shape_name)
        if shape_id && primitives.length != 1
          raise ArgumentError, "custom_shape id can only be assigned when one primitive is produced"
        end
        primitives.first[:id] ||= shape_id.to_sym if shape_id
        custom_shape_cache[cache_key] = deep_dup(primitives) if cache_key
        primitives
      end

      def param_schema_for(renderer)
        return renderer.shape_param_schema if renderer.respond_to?(:shape_param_schema)

        {}
      end

      private

      def custom_shape_cache
        @custom_shape_cache ||= {}
      end

      def custom_shape_cache_key(renderer:, params:, shape_id:, layer_name:, palette:, resolution:, globals:, shape_name:)
        [
          renderer_cache_identity(renderer),
          normalize_cache_value(params),
          shape_id&.to_sym,
          layer_name&.to_sym,
          normalize_cache_value(palette),
          normalize_cache_value(resolution),
          normalize_cache_value(globals),
          normalize_cache_value(shape_name)
        ]
      end

      def renderer_cache_identity(renderer)
        if renderer.is_a?(Module) && renderer.name
          [:module, renderer.name]
        else
          [:object, renderer.object_id]
        end
      end

      def normalize_cache_value(value)
        case value
        when Hash
          value.map { |key, entry| [key.to_s, normalize_cache_value(entry)] }.sort_by(&:first)
        when Array
          value.map { |entry| normalize_cache_value(entry) }
        when Symbol
          value.to_s
        else
          value
        end
      end

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, entry), output| output[key] = deep_dup(entry) }
        when Array
          value.map { |entry| deep_dup(entry) }
        else
          value
        end
      end

      def shape_definition(renderer)
        return unless renderer.is_a?(Symbol) || renderer.is_a?(String)
        return unless Vizcore.respond_to?(:resolve_shape)

        Vizcore.resolve_shape(renderer) || raise(ArgumentError, "Unknown custom shape: #{renderer.inspect}. Register it with `Vizcore.register_shape #{renderer.inspect}, ShapeClass`.")
      end

      def call_renderer(renderer, context, params)
        if renderer.respond_to?(:draw)
          return renderer.draw(context)
        end

        return renderer.call(context) if renderer.respond_to?(:call) && !renderer.is_a?(Class)

        instance = instantiate_renderer(renderer, params)
        return instance.draw(context) if instance.respond_to?(:draw)

        raise ArgumentError, "custom shape renderer must implement draw(context)"
      end

      def instantiate_renderer(renderer, params)
        renderer.new(**params)
      rescue ArgumentError
        renderer.new
      end

      def normalize_primitive(primitive, shape_name:)
        values = symbolize_keys(primitive)
        kind = values[:kind]&.to_sym
        unless SUPPORTED_PRIMITIVES.include?(kind)
          raise ArgumentError, "Custom shape `#{shape_name}` returned unsupported primitive kind: #{kind.inspect}"
        end

        values.merge(kind: kind)
      rescue TypeError
        raise ArgumentError, "Custom shape `#{shape_name}` returned a non-hash primitive"
      end

      def symbolize_keys(value)
        Hash(value).each_with_object({}) do |(key, entry), output|
          output[key.to_sym] = normalize_value(entry)
        end
      end

      def normalize_value(value)
        case value
        when Hash
          symbolize_keys(value)
        when Array
          value.map { |entry| normalize_value(entry) }
        else
          value
        end
      end
    end

    # Class methods added to custom shape classes.
    module ClassMethods
      def param(name, default: nil, range: nil, min: nil, max: nil, step: nil)
        key = name.to_sym
        range_min, range_max = range_values(range)
        metadata = { name: key }
        metadata[:default] = default unless default.nil?
        metadata[:min] = min.nil? ? range_min : min
        metadata[:max] = max.nil? ? range_max : max
        metadata[:step] = step unless step.nil?
        shape_param_schema[key] = metadata.compact
      end

      def shape_param_schema
        @shape_param_schema ||= {}
      end

      private

      def range_values(value)
        return [nil, nil] if value.nil?
        return [value.begin, value.end] if value.is_a?(Range)
        return value if value.is_a?(Array) && value.length == 2

        raise ArgumentError, "shape param range must be a Range or two-element Array"
      end
    end

    # Context passed into custom shape draw methods.
    class DrawContext
      def initialize(params:, param_schema: {}, shape_id: nil, layer_name: nil, palette: [], audio: {}, time: 0.0, frame: 0, resolution: [1280, 720], globals: {})
        @param_schema = symbolize_param_schema(param_schema)
        @params = normalize_params(default_params.merge(symbolize_hash(params)))
        @shape_id = shape_id&.to_sym
        @layer_name = layer_name
        @palette = Array(palette)
        @audio = AudioContext.new(audio)
        @time = Float(time || 0)
        @frame = Integer(frame || 0)
        @resolution = Array(resolution)
        @globals = symbolize_hash(globals)
        @builder = PrimitiveBuilder.new
      end

      attr_reader :params, :shape_id, :layer_name, :palette, :audio, :time, :frame, :resolution, :globals

      def param(name, default = nil)
        key = name.to_sym
        return @params[key] if @params.key?(key)

        default
      end

      def width
        resolution[0]
      end

      def height
        resolution[1]
      end

      def draw(&block)
        @builder.draw(&block)
      end

      def shapes
        @builder.shapes
      end

      %i[circle line rect polygon polyline path bezier star group].each do |method_name|
        define_method(method_name) do |*args, **options, &block|
          @builder.public_send(method_name, *args, **options, &block)
        end
      end

      private

      def default_params
        @param_schema.each_with_object({}) do |(key, metadata), output|
          output[key.to_sym] = metadata[:default] if metadata.key?(:default)
        end
      end

      def normalize_params(values)
        values.each_with_object({}) do |(key, value), output|
          symbol_key = key.to_sym
          metadata = @param_schema[symbol_key]
          output[symbol_key] = metadata ? normalize_param_value(symbol_key, value, metadata) : value
        end
      end

      def normalize_param_value(key, value, metadata)
        return value unless numeric_param?(metadata)

        numeric = numeric_param_value(key, value)
        min = numeric_metadata(metadata[:min])
        max = numeric_metadata(metadata[:max])
        raise ArgumentError, "shape param #{key} must be >= #{min}" if min && numeric < min
        raise ArgumentError, "shape param #{key} must be <= #{max}" if max && numeric > max

        numeric
      end

      def numeric_param_value(key, value)
        Float(value)
      rescue ArgumentError, TypeError
        raise ArgumentError, "shape param #{key} must be numeric"
      end

      def numeric_param?(metadata)
        %i[default min max step].any? do |key|
          metadata.key?(key) && numeric_metadata(metadata[key])
        end
      end

      def numeric_metadata(value)
        return nil if value.nil?

        numeric = Float(value)
        numeric if numeric.finite?
      rescue ArgumentError, TypeError
        nil
      end

      def symbolize_hash(value)
        Hash(value).each_with_object({}) { |(key, entry), output| output[key.to_sym] = entry }
      rescue TypeError
        {}
      end

      def symbolize_param_schema(value)
        Hash(value).each_with_object({}) do |(key, metadata), output|
          output[key.to_sym] = symbolize_hash(metadata)
        end
      rescue TypeError
        {}
      end
    end

    # Hash-like audio accessor for custom shape contexts.
    class AudioContext
      def initialize(payload)
        @payload = symbolize_hash(payload)
      end

      def amplitude
        numeric(@payload[:amplitude])
      end

      def bass
        numeric(band(:low))
      end

      def mid
        numeric(band(:mid))
      end

      def high
        numeric(band(:high))
      end

      def fft
        Array(@payload[:fft])
      end

      def beat?
        !!@payload[:beat]
      end

      def beat_pulse
        numeric(@payload[:beat_pulse])
      end

      def kick
        numeric(drum(:kick))
      end

      def snare
        numeric(drum(:snare))
      end

      def hihat
        numeric(drum(:hihat))
      end

      def bpm
        numeric(@payload[:bpm])
      end

      private

      def band(name)
        bands = symbolize_hash(@payload[:bands])
        bands[name]
      end

      def drum(name)
        drums = symbolize_hash(@payload[:drums])
        drums[name]
      end

      def numeric(value)
        Float(value || 0)
      rescue ArgumentError, TypeError
        0.0
      end

      def symbolize_hash(value)
        Hash(value).each_with_object({}) { |(key, entry), output| output[key.to_sym] = entry }
      rescue TypeError
        {}
      end
    end

    # Builder used by DrawContext for primitive arrays.
    class PrimitiveBuilder
      NO_ARGUMENT = Object.new.freeze

      def initialize
        @shapes = []
        @group_stack = [{}]
      end

      attr_reader :shapes

      def draw(&block)
        instance_eval(&block) if block
        shapes
      end

      def circle(id = nil, **options, &block)
        build_shape(:circle, shape_options(id, options), &block)
      end

      def line(id = nil, **options, &block)
        build_shape(:line, shape_options(id, options), &block)
      end

      def rect(id = nil, **options, &block)
        build_shape(:rect, shape_options(id, options), &block)
      end

      def polygon(id = nil, **options, &block)
        build_shape(:polygon, shape_options(id, options), &block)
      end

      def polyline(id = nil, **options, &block)
        build_shape(:polyline, shape_options(id, options).merge(closed: false), &block)
      end

      def path(id = nil, **options, &block)
        build_shape(:path, shape_options(id, options).merge(commands: []), &block)
      end

      def bezier(id = nil, from:, to:, control: nil, c1: nil, c2: nil, **options, &block)
        commands = [["M", *point_values(from)]]
        if control
          commands << ["Q", *point_values(control), *point_values(to)]
        elsif c1 && c2
          commands << ["C", *point_values(c1), *point_values(c2), *point_values(to)]
        else
          raise ArgumentError, "bezier requires either :control or both :c1 and :c2"
        end
        build_shape(:path, shape_options(id, options).merge(commands: commands), &block)
      end

      def star(id = nil, **options, &block)
        build_shape(:star, shape_options(id, options), &block)
      end

      def group(_id = nil, **attrs, &block)
        @group_stack << merge_group(current_group, normalize_group(attrs))
        instance_eval(&block) if block
        shapes
      ensure
        @group_stack.pop
      end

      def fill(value)
        target[:fill] = value.to_s
      end

      def stroke(value = NO_ARGUMENT, width: nil, color: nil)
        target[:stroke] = non_negative_number(value, :stroke) unless value.equal?(NO_ARGUMENT)
        target[:stroke_width] = non_negative_number(width, :stroke_width) unless width.nil?
        target[:stroke_color] = color.to_s unless color.nil?
        target
      end

      def blend(value)
        target[:blend] = value.to_sym
      end

      def opacity(value)
        if @current_shape || !target.key?(:opacity)
          target[:opacity] = number(value, :opacity)
        else
          target[:opacity] = number(target[:opacity], :opacity) * number(value, :opacity)
        end
      end

      def translate(*args, x: nil, y: nil)
        values = xy_args(args, x: x, y: y, name: :translate)
        target_transform[:translate] = @current_shape ? values : add_xy(target_transform[:translate], values)
      end

      def rotate(value)
        rotation = number(value, :rotate)
        target_transform[:rotate] = @current_shape ? rotation : number(target_transform[:rotate] || 0, :rotate) + rotation
      end

      def scale(value = NO_ARGUMENT, x: nil, y: nil)
        values = scale_args(value, x: x, y: y)
        target_transform[:scale] = @current_shape ? values : multiply_scale(target_transform[:scale], values)
      end

      def origin(*args, x: nil, y: nil)
        target_transform[:origin] = xy_args(args, x: x, y: y, name: :origin)
      end

      def move_to(x, y)
        append_path_command("M", x, y)
      end

      def line_to(x, y)
        append_path_command("L", x, y)
      end

      def horizontal_to(x)
        append_path_command("H", x)
      end

      def vertical_to(y)
        append_path_command("V", y)
      end

      def quad_to(cx, cy, x, y)
        append_path_command("Q", cx, cy, x, y)
      end

      def cubic_to(c1x, c1y, c2x, c2y, x, y)
        append_path_command("C", c1x, c1y, c2x, c2y, x, y)
      end

      def arc_to(rx, ry, rotation, large_arc, sweep, x, y)
        append_path_command("A", rx, ry, rotation, large_arc, sweep, x, y)
      end

      def close
        append_path_command("Z")
      end

      def method_missing(method_name, *args, &block)
        if @current_shape && block.nil? && args.length == 1
          @current_shape[method_name.to_sym] = args.first
          return args.first
        end

        super
      end

      def respond_to_missing?(_method_name, include_private = false)
        !!@current_shape || super
      end

      private

      def build_shape(kind, options, &block)
        shape = { kind: kind }.merge(options)
        previous_shape = @current_shape
        @current_shape = shape
        instance_eval(&block) if block
        shape = apply_group(shape)
        @shapes << shape
        shape
      ensure
        @current_shape = previous_shape
      end

      def shape_options(id, options)
        return options if id.nil?

        raise ArgumentError, "shape id specified twice" if options.key?(:id)

        options.merge(id: id.to_sym)
      end

      def normalize_group(attrs)
        attrs.each_with_object({}) { |(key, value), output| output[key.to_sym] = value }
      end

      def merge_group(parent, child)
        merged = deep_dup(parent)
        child.each do |key, value|
          if key == :opacity && merged.key?(:opacity)
            merged[:opacity] = number(merged[:opacity], :opacity) * number(value, :opacity)
          else
            merged[key] = value
          end
        end
        merged
      end

      def apply_group(shape)
        group = current_group
        merged = deep_dup(shape)
        STYLE_KEYS.each do |key|
          next unless group.key?(key)

          if key == :opacity && merged.key?(:opacity)
            merged[:opacity] = number(group[:opacity], :opacity) * number(merged[:opacity], :opacity)
          else
            merged[key] = group[key] unless merged.key?(key)
          end
        end
        merged[:transform] = compose_transform(group[:transform], merged[:transform]) if group[:transform]
        merged
      end

      def compose_transform(parent, child)
        return deep_dup(child || {}) unless parent

        output = deep_dup(parent)
        child = child || {}
        output[:translate] = add_xy(parent[:translate], child[:translate]) if child.key?(:translate)
        output[:origin] = child[:origin] if child.key?(:origin)
        output[:rotate] = number(parent[:rotate] || 0, :rotate) + number(child[:rotate] || 0, :rotate) if child.key?(:rotate)
        output[:scale] = multiply_scale(parent[:scale], child[:scale]) if child.key?(:scale)
        output
      end

      def add_xy(parent, child)
        parent = parent || {}
        child = child || {}
        {
          x: number(parent[:x] || 0, :x) + number(child[:x] || 0, :x),
          y: number(parent[:y] || 0, :y) + number(child[:y] || 0, :y)
        }
      end

      def multiply_scale(parent, child)
        parent = scale_pair(parent)
        child = scale_pair(child)
        { x: parent[:x] * child[:x], y: parent[:y] * child[:y] }
      end

      def scale_pair(value)
        return { x: number(value[:x] || 1, :scale), y: number(value[:y] || 1, :scale) } if value.is_a?(Hash)

        scale = number(value || 1, :scale)
        { x: scale, y: scale }
      end

      def target
        @current_shape || current_group
      end

      def target_transform
        target[:transform] ||= {}
      end

      def current_group
        @group_stack.last
      end

      def append_path_command(command, *values)
        raise ArgumentError, "#{command} is only available inside a path shape" unless @current_shape&.fetch(:kind) == :path

        @current_shape[:commands] ||= []
        @current_shape[:commands] << [command, *values]
      end

      def xy_args(args, x:, y:, name:)
        if args.length == 2
          return { x: number(args[0], :"#{name}.x"), y: number(args[1], :"#{name}.y") }
        end

        raise ArgumentError, "#{name} expects x/y keywords or two numeric arguments" if args.any?

        { x: number(x || 0, :"#{name}.x"), y: number(y || 0, :"#{name}.y") }
      end

      def scale_args(value, x:, y:)
        if value.equal?(NO_ARGUMENT)
          return { x: number(x || 1, :"scale.x"), y: number(y || 1, :"scale.y") }
        end

        raise ArgumentError, "scale accepts either a value or x/y keywords" unless x.nil? && y.nil?

        number(value, :scale)
      end

      def point_values(value)
        values = Array(value)
        raise ArgumentError, "point must contain x and y" unless values.length == 2

        values
      end

      def number(value, name)
        Float(value)
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{name} must be numeric"
      end

      def non_negative_number(value, name)
        numeric = number(value, name)
        raise ArgumentError, "#{name} must be non-negative" if numeric.negative?

        numeric
      end

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, entry), output| output[key] = deep_dup(entry) }
        when Array
          value.map { |entry| deep_dup(entry) }
        else
          value
        end
      end
    end
  end

  @shape_registry = {}

  class << self
    def register_shape(name, klass = nil, &block)
      raise ArgumentError, "register_shape requires a class/module or block" if klass.nil? && block.nil?
      raise ArgumentError, "register_shape accepts either a class/module or block" if klass && block

      key = name.to_sym
      @shape_registry[key] = Shape::Definition.new(name: key, renderer: klass || block)
    end

    def resolve_shape(name)
      @shape_registry[name.to_sym]
    end
  end
end
