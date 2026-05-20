# frozen_string_literal: true

require_relative "png_writer"

module Vizcore
  module Renderer
    # Renders a deterministic software preview PNG from a scene frame.
    class SnapshotRenderer
      DEFAULT_WIDTH = 1280
      DEFAULT_HEIGHT = 720
      PATH_DEFAULT_MAX_SEGMENTS = 4096
      PATH_HARD_MAX_SEGMENTS = 65_536
      PALETTE = [
        [56, 189, 248],
        [225, 29, 72],
        [101, 255, 176],
        [244, 114, 182],
        [250, 204, 21]
      ].freeze

      def initialize(width: DEFAULT_WIDTH, height: DEFAULT_HEIGHT)
        @width = normalize_dimension(width)
        @height = normalize_dimension(height)
      end

      attr_reader :width, :height

      # @param scene [Hash]
      # @param audio [Hash]
      # @return [String] PNG bytes
      def render(scene:, audio:)
        canvas = Canvas.new(width: width, height: height)
        canvas.fill_gradient(background_top(audio), background_bottom(audio))
        layers = Array(scene[:layers] || scene["layers"])
        layers = [default_layer] if layers.empty?
        layers.each_with_index { |layer, index| render_layer(canvas, layer, audio, index) }
        PngWriter.encode(width: width, height: height, rgba: canvas.bytes)
      end

      private

      def render_layer(canvas, layer, audio, index)
        type = (layer[:type] || layer["type"] || "geometry").to_s
        color = layer_color(layer, audio, index)

        case type
        when "shader"
          render_shader_layer(canvas, audio, color, index)
        when "particle_field"
          render_particle_layer(canvas, layer, audio, color)
        when "text"
          render_text_layer(canvas, layer, audio, color)
        when "svg", "svg_layer", "image", "image_layer", "photo", "video", "video_layer", "footage"
          render_image_layer(canvas, layer, audio, color)
        when "waveform", "waveform_layer"
          render_waveform_layer(canvas, layer, audio, color)
        when "spectrogram", "spectrogram_layer"
          render_spectrogram_layer(canvas, layer, audio, color)
        when "shape", "shapes", "shape_layer"
          render_shape_layer(canvas, layer, audio, color)
        when "mesh", "mesh_layer", "preset_mesh"
          render_mesh_layer(canvas, layer, audio, color, index)
        else
          render_geometry_layer(canvas, audio, color, index)
        end
      end

      def render_shader_layer(canvas, audio, color, index)
        amplitude = clamp(audio[:amplitude])
        y_base = height * (0.35 + index * 0.12)
        5.times do |wave_index|
          alpha = 0.16 + amplitude * 0.18
          offset = wave_index * height * 0.055
          canvas.draw_wave(y_base + offset, amplitude: amplitude, color: color, alpha: alpha)
        end
      end

      def render_particle_layer(canvas, layer, audio, color)
        amplitude = clamp(audio[:amplitude])
        count = [[Integer(layer.dig(:params, :count) || layer.dig("params", "count") || 420), 80].max, 900].min
        count.times do |index|
          x = (Math.sin(index * 12.9898) * 43_758.5453).abs % width
          y = (Math.sin(index * 78.233) * 12_345.6789).abs % height
          radius = 1 + (index % 3) + (amplitude * 2).round
          canvas.fill_circle(x, y, radius, color, alpha: 0.35 + amplitude * 0.45)
        end
      rescue ArgumentError, TypeError
        nil
      end

      def render_text_layer(canvas, layer, audio, color)
        params = Hash(layer[:params] || layer["params"] || {})
        content = params[:content] || params["content"] || layer[:name] || layer["name"] || "Vizcore"
        canvas.draw_label(
          content.to_s,
          x: width * 0.5,
          y: height * 0.72,
          color: color,
          alpha: 0.62 + clamp(audio[:beat_pulse]) * 0.28,
          letter_spacing: normalize_letter_spacing(params)
        )
      end

      def render_image_layer(canvas, layer, audio, color)
        params = Hash(layer[:params] || layer["params"] || {})
        label = params[:file] || params["file"] || layer[:name] || layer["name"] || "image"
        scale = Float(params[:scale] || params["scale"] || 1).clamp(0.1, 4.0)
        pulse = clamp(audio[:beat_pulse])
        size = [width, height].min * (0.18 + pulse * 0.06) * scale
        x = width * 0.5
        y = height * 0.5
        canvas.draw_rect_outline(x - size / 2, y - size / 2, size, size, color, alpha: 0.72)
        canvas.draw_label(File.basename(label.to_s), x: x, y: y + size * 0.62, color: color, alpha: 0.66)
      rescue ArgumentError, TypeError
        nil
      end

      def render_waveform_layer(canvas, layer, audio, color)
        params = Hash(layer[:params] || layer["params"] || {})
        amplitude = clamp(audio[:amplitude])
        style = (params[:style] || params["style"] || "line").to_s
        height_scale = normalize_waveform_height(params)
        alpha = 0.45 + amplitude * 0.35
        y_base = height * 0.5

        canvas.draw_wave(y_base, amplitude: amplitude, color: color, alpha: alpha, height_scale: height_scale)
        return unless %w[mirror ribbon].include?(style)

        canvas.draw_wave(y_base, amplitude: amplitude, color: color, alpha: alpha * 0.68, height_scale: -height_scale)
      rescue ArgumentError, TypeError
        nil
      end

      def render_spectrogram_layer(canvas, layer, audio, color)
        params = Hash(layer[:params] || layer["params"] || {})
        fft = Array(audio[:fft] || audio["fft"])
        bins = [[Integer(params[:bins] || params["bins"] || 32), 8].max, 96].min
        gain = Float(params[:gain] || params["gain"] || 1).clamp(0.1, 8.0)
        band_width = width.to_f / bins
        rows = 18
        row_height = height * 0.5 / rows
        top = height * 0.22

        rows.times do |row|
          age = row.to_f / [rows - 1, 1].max
          bins.times do |bin|
            value = clamp(Float(fft[bin % [fft.length, 1].max] || 0) * gain)
            alpha = (0.08 + value * 0.52) * (1.0 - age * 0.62)
            x = bin * band_width
            y = top + row * row_height
            canvas.fill_rect(x, y, band_width.ceil + 1, row_height.ceil + 1, color, alpha: alpha)
          end
        end
      rescue ArgumentError, TypeError
        nil
      end

      def render_shape_layer(canvas, layer, audio, color)
        params = Hash(layer[:params] || layer["params"] || {})
        shapes = Array(params[:shapes] || params["shapes"])
        context = shape_coordinate_context(params)
        pulse = clamp(audio[:beat_pulse])
        alpha = 0.58 + pulse * 0.24

        shapes.each do |shape|
          shape_hash = Hash(shape)
          case (shape_hash[:kind] || shape_hash["kind"]).to_s
          when "circle"
            render_circle_shape(canvas, shape_hash, color, alpha, context)
          when "line"
            render_line_shape(canvas, shape_hash, color, alpha, context)
          when "rect"
            render_rect_shape(canvas, shape_hash, color, alpha, context)
          when "polygon", "polyline"
            render_polygon_shape(canvas, shape_hash, color, alpha, context)
          when "path"
            render_path_shape(canvas, shape_hash, color, alpha, context)
          when "star"
            render_star_shape(canvas, shape_hash, color, alpha, context)
          end
        end
      rescue ArgumentError, TypeError
        nil
      end

      def render_circle_shape(canvas, shape, color, alpha, context)
        count = [[Integer(shape[:count] || shape["count"] || 1), 1].max, 32].min
        radius = shape_length(shape[:radius] || shape["radius"] || 100, context, :radius)
        center = shape_point(shape[:x] || shape["x"] || 0, shape[:y] || shape["y"] || 0, context)

        count.times do |index|
          ring_radius = radius * ((index + 1).to_f / count)
          render_polyline_shape(canvas, circle_points(center, ring_radius), shape, color, alpha, context, closed: true)
        end
      end

      def render_line_shape(canvas, shape, color, alpha, context)
        defaults = context[:units] == :legacy || context[:units] == :ndc ? [-0.8, 0, 0.8, 0] : [-100, 0, 100, 0]
        from = shape_point(shape[:x1] || shape["x1"] || defaults[0], shape[:y1] || shape["y1"] || defaults[1], context)
        to = shape_point(shape[:x2] || shape["x2"] || defaults[2], shape[:y2] || shape["y2"] || defaults[3], context)
        draw_shape_segment(canvas, from, to, shape, color, alpha, context)
      end

      def render_rect_shape(canvas, shape, color, alpha, context)
        center = shape_point(shape[:x] || shape["x"] || 0, shape[:y] || shape["y"] || 0, context)
        half_width = shape_length(shape[:width] || shape["width"] || 100, context, :x) / 2.0
        half_height = shape_length(shape[:height] || shape["height"] || 100, context, :y) / 2.0
        points = [
          [center[0] - half_width, center[1] - half_height],
          [center[0] + half_width, center[1] - half_height],
          [center[0] + half_width, center[1] + half_height],
          [center[0] - half_width, center[1] + half_height]
        ]
        render_polyline_shape(canvas, points, shape, color, alpha, context, closed: true)
      end

      def render_polygon_shape(canvas, shape, color, alpha, context)
        points = Array(shape[:points] || shape["points"]).filter_map do |point|
          values = Array(point)
          next if values.length < 2

          shape_point(values[0], values[1], context)
        end
        closed = (shape[:kind] || shape["kind"]).to_s == "polygon" ? shape.fetch(:closed, shape.fetch("closed", true)) : false
        render_polyline_shape(canvas, points, shape, color, alpha, context, closed: closed)
      end

      def render_star_shape(canvas, shape, color, alpha, context)
        tips = [[Integer(shape[:points] || shape["points"] || 5), 3].max, 128].min
        center = shape_point(shape[:x] || shape["x"] || 0, shape[:y] || shape["y"] || 0, context)
        radius = shape_length(shape[:radius] || shape["radius"] || 100, context, :radius)
        inner_radius = shape_length(shape[:inner_radius] || shape["inner_radius"] || Float(shape[:radius] || shape["radius"] || 100) * 0.5, context, :radius)
        rotation = Float(shape[:rotation] || shape["rotation"] || -90) * Math::PI / 180.0
        points = (tips * 2).times.map do |index|
          angle = rotation + (index.to_f / (tips * 2)) * Math::PI * 2
          point_radius = index.even? ? radius : inner_radius
          [center[0] + Math.cos(angle) * point_radius, center[1] - Math.sin(angle) * point_radius]
        end
        render_polyline_shape(canvas, points, shape, color, alpha, context, closed: true)
      end

      def render_path_shape(canvas, shape, color, alpha, context)
        detail = [[Integer(shape[:detail] || shape["detail"] || 32), 4].max, 128].min
        segment_budget = { remaining: path_segment_limit(shape) }
        current = nil
        subpath_start = nil
        Array(shape[:commands] || shape["commands"]).each do |entry|
          command, *values = Array(entry)
          values = values.map { |value| Float(value) }
          case command.to_s.upcase
          when "M"
            current = values.first(2)
            subpath_start = current
          when "L"
            next unless current && values.length >= 2

            current = draw_raw_path_segment(canvas, current, values.first(2), shape, color, alpha, context, segment_budget)
          when "H"
            next unless current && values.length >= 1

            current = draw_raw_path_segment(canvas, current, [values[0], current[1]], shape, color, alpha, context, segment_budget)
          when "V"
            next unless current && values.length >= 1

            current = draw_raw_path_segment(canvas, current, [current[0], values[0]], shape, color, alpha, context, segment_budget)
          when "Q"
            next unless current && values.length >= 4

            current = draw_quadratic_path(canvas, current, values, detail, shape, color, alpha, context, segment_budget)
          when "C"
            next unless current && values.length >= 6

            current = draw_cubic_path(canvas, current, values, detail, shape, color, alpha, context, segment_budget)
          when "A"
            next unless current && values.length >= 7

            current = draw_arc_path(canvas, current, values, detail, shape, color, alpha, context, segment_budget)
          when "Z"
            if current && subpath_start
              current = draw_raw_path_segment(canvas, current, subpath_start, shape, color, alpha, context, segment_budget)
            end
          end
        end
      end

      def render_polyline_shape(canvas, points, shape, color, alpha, context, closed:)
        return if points.length < 2

        points.each_cons(2) { |from, to| draw_shape_segment(canvas, from, to, shape, color, alpha, context) }
        draw_shape_segment(canvas, points.last, points.first, shape, color, alpha, context) if closed && points.length > 2
      end

      def draw_raw_path_segment(canvas, from, to, shape, color, alpha, context, segment_budget = nil)
        return to if segment_budget && segment_budget[:remaining] <= 0

        draw_shape_segment(canvas, shape_point(from[0], from[1], context), shape_point(to[0], to[1], context), shape, color, alpha, context)
        segment_budget[:remaining] -= 1 if segment_budget
        to
      end

      def draw_quadratic_path(canvas, current, values, detail, shape, color, alpha, context, segment_budget = nil)
        previous = current
        control = values.first(2)
        endpoint = values.last(2)
        1.upto(detail) do |step|
          break if segment_budget && segment_budget[:remaining] <= 0

          t = step.to_f / detail
          point = [
            quadratic_point(current[0], control[0], endpoint[0], t),
            quadratic_point(current[1], control[1], endpoint[1], t)
          ]
          draw_raw_path_segment(canvas, previous, point, shape, color, alpha, context, segment_budget)
          previous = point
        end
        endpoint
      end

      def draw_cubic_path(canvas, current, values, detail, shape, color, alpha, context, segment_budget = nil)
        previous = current
        c1 = values[0, 2]
        c2 = values[2, 2]
        endpoint = values[4, 2]
        1.upto(detail) do |step|
          break if segment_budget && segment_budget[:remaining] <= 0

          t = step.to_f / detail
          point = [
            cubic_point(current[0], c1[0], c2[0], endpoint[0], t),
            cubic_point(current[1], c1[1], c2[1], endpoint[1], t)
          ]
          draw_raw_path_segment(canvas, previous, point, shape, color, alpha, context, segment_budget)
          previous = point
        end
        endpoint
      end

      def draw_arc_path(canvas, current, values, detail, shape, color, alpha, context, segment_budget = nil)
        endpoint = values[5, 2]
        arc = svg_arc_description(
          from: current,
          to: endpoint,
          rx: values[0],
          ry: values[1],
          x_axis_rotation: values[2],
          large_arc: arc_flag(values[3]),
          sweep: arc_flag(values[4])
        )
        unless arc
          return draw_raw_path_segment(canvas, current, endpoint, shape, color, alpha, context, segment_budget)
        end

        previous = current
        segments = svg_arc_segment_count(arc, detail)
        1.upto(segments) do |step|
          break if segment_budget && segment_budget[:remaining] <= 0

          point = svg_arc_point(arc, step.to_f / segments)
          draw_raw_path_segment(canvas, previous, point, shape, color, alpha, context, segment_budget)
          previous = point
        end
        endpoint
      end

      def path_segment_limit(shape)
        raw_value = shape[:max_segments] || shape["max_segments"] || PATH_DEFAULT_MAX_SEGMENTS
        [[Integer(raw_value), 1].max, PATH_HARD_MAX_SEGMENTS].min
      rescue ArgumentError, TypeError
        PATH_DEFAULT_MAX_SEGMENTS
      end

      def draw_shape_segment(canvas, from, to, shape, color, alpha, context)
        from = apply_shape_transform(from, shape, context)
        to = apply_shape_transform(to, shape, context)
        canvas.draw_line(from[0], from[1], to[0], to[1], color, alpha: alpha * shape_opacity(shape))
      end

      def shape_coordinate_context(params)
        units = (params[:units] || params["units"]).to_s.strip.downcase
        version = Integer(params[:shape_schema_version] || params["shape_schema_version"] || 1)
        { units: (units.empty? ? (version >= 2 ? :logical : :legacy) : units.to_sym) }
      rescue ArgumentError, TypeError
        { units: :legacy }
      end

      def shape_point(x, y, context)
        [shape_coordinate(x, context, :x), shape_coordinate(y, context, :y)]
      end

      def shape_coordinate(value, context, axis)
        numeric = Float(value || 0)
        case context[:units]
        when :ndc
          axis == :x ? width * 0.5 + numeric * width * 0.5 : height * 0.5 - numeric * height * 0.5
        when :logical, :center, :center_origin, :px
          axis == :x ? width * 0.5 + numeric : height * 0.5 - numeric
        when :screen, :canvas, :viewport
          numeric
        else
          legacy_shape_coordinate(numeric, axis)
        end
      end

      def legacy_shape_coordinate(value, axis)
        return axis == :x ? width * 0.5 + value * width * 0.5 : height * 0.5 - value * height * 0.5 if value.abs <= 1.5

        value
      end

      def shape_length(value, context, _axis)
        numeric = Float(value || 0).abs
        return numeric * [width, height].min * 0.5 if context[:units] == :ndc || numeric <= 2

        numeric
      end

      def circle_points(center, radius)
        segments = 96
        segments.times.map do |index|
          angle = (index.to_f / segments) * Math::PI * 2
          [center[0] + Math.cos(angle) * radius, center[1] + Math.sin(angle) * radius]
        end
      end

      def apply_shape_transform(point, shape, context)
        transform = shape_transform(shape, context)
        shifted_x = (point[0] - transform[:origin][0]) * transform[:scale][:x]
        shifted_y = (point[1] - transform[:origin][1]) * transform[:scale][:y]
        radians = -transform[:rotate] * Math::PI / 180.0
        cos = Math.cos(radians)
        sin = Math.sin(radians)
        rotated_x = shifted_x * cos - shifted_y * sin
        rotated_y = shifted_x * sin + shifted_y * cos

        [
          rotated_x + transform[:origin][0] + transform[:translate][:x],
          rotated_y + transform[:origin][1] + transform[:translate][:y]
        ]
      end

      def shape_transform(shape, context)
        transform = Hash(shape[:transform] || shape["transform"] || {})
        {
          translate: shape_vector_pair(shape_hash_value(transform, :translate) || shape_hash_value(shape, :translate), context),
          origin: shape_origin_pair(shape_hash_value(transform, :origin) || shape_hash_value(shape, :origin), context),
          rotate: Float(shape_hash_value(transform, :rotate) || shape_hash_value(shape, :rotate) || shape_hash_value(shape, :rotation) || 0),
          scale: shape_scale(shape_hash_value(transform, :scale) || shape_hash_value(shape, :scale))
        }
      end

      def shape_vector_pair(value, context)
        if value.is_a?(Array)
          return { x: shape_vector(value[0], context, :x), y: shape_vector(value[1], context, :y) }
        end

        values = value.is_a?(Hash) ? value : {}
        { x: shape_vector(shape_hash_value(values, :x) || 0, context, :x), y: shape_vector(shape_hash_value(values, :y) || 0, context, :y) }
      end

      def shape_origin_pair(value, context)
        if value.is_a?(Array)
          return shape_point(value[0], value[1], context)
        end

        values = value.is_a?(Hash) ? value : {}
        shape_point(shape_hash_value(values, :x) || 0, shape_hash_value(values, :y) || 0, context)
      end

      def shape_vector(value, context, axis)
        numeric = Float(value || 0)
        case context[:units]
        when :ndc
          axis == :x ? numeric * width * 0.5 : -numeric * height * 0.5
        else
          axis == :x ? numeric : -numeric
        end
      end

      def shape_scale(value)
        if value.is_a?(Hash)
          return {
            x: Float(shape_hash_value(value, :x) || 1).clamp(-8.0, 8.0),
            y: Float(shape_hash_value(value, :y) || 1).clamp(-8.0, 8.0)
          }
        end

        scale = Float(value || 1).clamp(-8.0, 8.0)
        { x: scale, y: scale }
      end

      def shape_opacity(shape)
        Float(shape[:opacity] || shape["opacity"] || 1).clamp(0.0, 1.0)
      rescue ArgumentError, TypeError
        1.0
      end

      def shape_hash_value(hash, key)
        hash[key] || hash[key.to_s]
      end

      def quadratic_point(from, control, to, t)
        inv = 1.0 - t
        inv * inv * from + 2 * inv * t * control + t * t * to
      end

      def cubic_point(from, c1, c2, to, t)
        inv = 1.0 - t
        inv * inv * inv * from + 3 * inv * inv * t * c1 + 3 * inv * t * t * c2 + t * t * t * to
      end

      def svg_arc_description(from:, to:, rx:, ry:, x_axis_rotation:, large_arc:, sweep:)
        return if same_point?(from, to)

        radius_x = Float(rx || 0).abs
        radius_y = Float(ry || 0).abs
        return if radius_x <= 0 || radius_y <= 0

        rotation = Float(x_axis_rotation || 0) * Math::PI / 180.0
        cos = Math.cos(rotation)
        sin = Math.sin(rotation)
        dx = (from[0] - to[0]) / 2.0
        dy = (from[1] - to[1]) / 2.0
        x1p = cos * dx + sin * dy
        y1p = -sin * dx + cos * dy

        scale = (x1p * x1p / (radius_x * radius_x)) + (y1p * y1p / (radius_y * radius_y))
        if scale > 1
          multiplier = Math.sqrt(scale)
          radius_x *= multiplier
          radius_y *= multiplier
        end

        center = svg_arc_center(
          from: from,
          to: to,
          radius_x: radius_x,
          radius_y: radius_y,
          x1p: x1p,
          y1p: y1p,
          rotation_cos: cos,
          rotation_sin: sin,
          large_arc: large_arc,
          sweep: sweep
        )
        return unless center

        start_vector = [(x1p - center[:cxp]) / radius_x, (y1p - center[:cyp]) / radius_y]
        end_vector = [(-x1p - center[:cxp]) / radius_x, (-y1p - center[:cyp]) / radius_y]
        start_angle = vector_angle([1.0, 0.0], start_vector)
        delta_angle = vector_angle(start_vector, end_vector)
        delta_angle -= Math::PI * 2 if !sweep && delta_angle.positive?
        delta_angle += Math::PI * 2 if sweep && delta_angle.negative?

        {
          cx: center[:cx],
          cy: center[:cy],
          rx: radius_x,
          ry: radius_y,
          rotation: rotation,
          start_angle: start_angle,
          delta_angle: delta_angle
        }
      rescue ArgumentError, TypeError
        nil
      end

      def svg_arc_center(from:, to:, radius_x:, radius_y:, x1p:, y1p:, rotation_cos:, rotation_sin:, large_arc:, sweep:)
        rx2 = radius_x * radius_x
        ry2 = radius_y * radius_y
        x1p2 = x1p * x1p
        y1p2 = y1p * y1p
        denominator = rx2 * y1p2 + ry2 * x1p2
        return if denominator.zero?

        numerator = [rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2, 0.0].max
        sign = large_arc == sweep ? -1.0 : 1.0
        coefficient = sign * Math.sqrt(numerator / denominator)
        cxp = coefficient * ((radius_x * y1p) / radius_y)
        cyp = coefficient * (-(radius_y * x1p) / radius_x)
        {
          cxp: cxp,
          cyp: cyp,
          cx: rotation_cos * cxp - rotation_sin * cyp + (from[0] + to[0]) / 2.0,
          cy: rotation_sin * cxp + rotation_cos * cyp + (from[1] + to[1]) / 2.0
        }
      end

      def svg_arc_point(arc, progress)
        angle = arc[:start_angle] + arc[:delta_angle] * progress
        cos_rotation = Math.cos(arc[:rotation])
        sin_rotation = Math.sin(arc[:rotation])
        x = Math.cos(angle) * arc[:rx]
        y = Math.sin(angle) * arc[:ry]
        [
          arc[:cx] + cos_rotation * x - sin_rotation * y,
          arc[:cy] + sin_rotation * x + cos_rotation * y
        ]
      end

      def svg_arc_segment_count(arc, detail)
        [((arc[:delta_angle].abs / (Math::PI * 2)) * detail).ceil, 1].max
      end

      def vector_angle(from, to)
        cross = from[0] * to[1] - from[1] * to[0]
        dot = from[0] * to[0] + from[1] * to[1]
        Math.atan2(cross, dot)
      end

      def same_point?(from, to)
        (from[0] - to[0]).abs < 1e-9 && (from[1] - to[1]).abs < 1e-9
      end

      def arc_flag(value)
        !Float(value || 0).zero?
      rescue ArgumentError, TypeError
        false
      end

      def render_mesh_layer(canvas, layer, audio, color, index)
        params = Hash(layer[:params] || layer["params"] || {})
        amplitude = clamp(audio[:amplitude])
        high = audio.dig(:bands, :high) || audio.dig("bands", "high")
        deform = clamp(params[:deform] || params["deform"] || high || amplitude)
        scale = Float(params[:scale] || params["scale"] || 1).clamp(0.1, 3.0)
        radius = [width, height].min * (0.20 + amplitude * 0.08 + deform * 0.08) * scale
        cx = width * (0.5 + (index - 1) * 0.06)
        cy = height * 0.48
        top = [cx, cy - radius * 0.62]
        bottom = [cx, cy + radius * 0.62]
        ring = 6.times.map do |point_index|
          angle = (point_index.to_f / 6) * Math::PI * 2 + Math::PI / 6
          [cx + Math.cos(angle) * radius * 0.72, cy + Math.sin(angle) * radius * 0.36]
        end

        ring.each_with_index do |point, point_index|
          next_point = ring[(point_index + 1) % ring.length]
          canvas.draw_line(point[0], point[1], next_point[0], next_point[1], color, alpha: 0.62)
          canvas.draw_line(top[0], top[1], point[0], point[1], color, alpha: 0.54)
          canvas.draw_line(bottom[0], bottom[1], next_point[0], next_point[1], color, alpha: 0.42)
        end

        3.times do |point_index|
          from = ring[point_index]
          to = ring[point_index + 3]
          canvas.draw_line(from[0], from[1], to[0], to[1], color, alpha: 0.32 + deform * 0.2)
        end
      rescue ArgumentError, TypeError
        nil
      end

      def render_geometry_layer(canvas, audio, color, index)
        amplitude = clamp(audio[:amplitude])
        size = [width, height].min * (0.22 + amplitude * 0.18)
        cx = width * (0.5 + (index - 1) * 0.08)
        cy = height * 0.48
        offset = size * 0.24
        canvas.draw_rect_outline(cx - size / 2, cy - size / 2, size, size, color, alpha: 0.78)
        canvas.draw_rect_outline(cx - size / 2 + offset, cy - size / 2 - offset, size, size, color, alpha: 0.46)
        4.times do |corner|
          x1 = cx - size / 2 + (corner.even? ? 0 : size)
          y1 = cy - size / 2 + (corner < 2 ? 0 : size)
          canvas.draw_line(x1, y1, x1 + offset, y1 - offset, color, alpha: 0.55)
        end
      end

      def background_top(audio)
        amplitude = clamp(audio[:amplitude])
        high = clamp(audio.dig(:bands, :high))
        [4 + (amplitude * 22).round, 10 + (high * 38).round, 24 + (amplitude * 34).round]
      end

      def background_bottom(audio)
        low = clamp(audio.dig(:bands, :low))
        [1 + (low * 30).round, 4 + (low * 18).round, 12 + (low * 44).round]
      end

      def layer_color(layer, audio, index)
        base = configured_layer_color(layer, index) || PALETTE[index % PALETTE.length]
        beat = clamp(audio[:beat_pulse])
        name_factor = (layer[:shader] || layer["shader"] || layer[:name] || layer["name"]).to_s.bytes.sum % 38
        base.map { |value| [[value + name_factor + (beat * 30).round, 255].min, 0].max }
      end

      def configured_layer_color(layer, index)
        params = Hash(layer[:params] || layer["params"] || {})
        color = configured_color(params) || palette_color(params, index)
        parse_hex_color(color)
      rescue StandardError
        nil
      end

      def configured_color(params)
        [params[:color], params["color"]].map { |value| value.to_s.strip }.find { |value| !value.empty? }
      end

      def palette_color(params, index)
        palette = Array(params[:palette] || params["palette"]).map { |color| color.to_s.strip }.reject(&:empty?)
        return nil if palette.empty?

        palette[index % palette.length]
      end

      def parse_hex_color(value)
        match = value.to_s.strip.match(/\A#(?<hex>[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\z/)
        return nil unless match

        hex = match[:hex]
        hex = hex.chars.map { |char| "#{char}#{char}" }.join if hex.length == 3
        [hex[0, 2], hex[2, 2], hex[4, 2]].map { |component| component.to_i(16) }
      end

      def default_layer
        { type: "geometry", name: "snapshot" }
      end

      def normalize_dimension(value)
        Integer(value).clamp(64, 4096)
      rescue ArgumentError, TypeError
        DEFAULT_WIDTH
      end

      def clamp(value)
        Float(value || 0).clamp(0.0, 1.0)
      rescue ArgumentError, TypeError
        0.0
      end

      def normalize_letter_spacing(params)
        Float(params[:letter_spacing] || params["letter_spacing"] || 0).clamp(0.0, 96.0)
      rescue ArgumentError, TypeError
        0.0
      end

      def normalize_waveform_height(params)
        Float(params[:height] || params["height"] || 0.46).clamp(0.05, 1.1)
      rescue ArgumentError, TypeError
        0.46
      end

      # Tiny RGBA canvas with alpha blending and a few primitive drawing helpers.
      class Canvas
        def initialize(width:, height:)
          @width = width
          @height = height
          @bytes = String.new(capacity: width * height * 4, encoding: Encoding::BINARY)
          @bytes << ([0, 0, 0, 255].pack("C4") * (width * height))
        end

        attr_reader :width, :height, :bytes

        def fill_gradient(top, bottom)
          height.times do |y|
            t = y.to_f / [height - 1, 1].max
            color = 3.times.map { |index| interpolate(top[index], bottom[index], t).round }
            width.times { |x| set_pixel(x, y, color, 255) }
          end
        end

        def draw_wave(y_base, amplitude:, color:, alpha:, height_scale: 1.0)
          previous = nil
          width.times do |x|
            phase = (x.to_f / width) * Math::PI * 4.0
            y = y_base + Math.sin(phase) * height * (0.06 + amplitude * 0.08) * height_scale
            draw_line(previous[0], previous[1], x, y, color, alpha: alpha) if previous
            previous = [x, y]
          end
        end

        def draw_rect_outline(x, y, rect_width, rect_height, color, alpha:)
          draw_line(x, y, x + rect_width, y, color, alpha: alpha)
          draw_line(x + rect_width, y, x + rect_width, y + rect_height, color, alpha: alpha)
          draw_line(x + rect_width, y + rect_height, x, y + rect_height, color, alpha: alpha)
          draw_line(x, y + rect_height, x, y, color, alpha: alpha)
        end

        def draw_circle_outline(cx, cy, radius, color, alpha:)
          segments = 96
          previous = nil
          (0..segments).each do |index|
            angle = (index.to_f / segments) * Math::PI * 2
            point = [cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius]
            draw_line(previous[0], previous[1], point[0], point[1], color, alpha: alpha) if previous
            previous = point
          end
        end

        def fill_rect(x, y, rect_width, rect_height, color, alpha:)
          start_x = x.round
          end_x = (x + rect_width).round
          start_y = y.round
          end_y = (y + rect_height).round
          start_y.upto(end_y) do |py|
            start_x.upto(end_x) { |px| blend_pixel(px, py, color, alpha) }
          end
        end

        def draw_line(x1, y1, x2, y2, color, alpha:)
          x1 = x1.round
          y1 = y1.round
          x2 = x2.round
          y2 = y2.round
          steps = [(x2 - x1).abs, (y2 - y1).abs].max
          return blend_pixel(x1, y1, color, alpha) if steps.zero?

          steps.times do |step|
            t = step.to_f / steps
            blend_pixel(interpolate(x1, x2, t).round, interpolate(y1, y2, t).round, color, alpha)
          end
        end

        def fill_circle(cx, cy, radius, color, alpha:)
          cx = cx.round
          cy = cy.round
          radius = radius.round
          (cy - radius).upto(cy + radius) do |y|
            (cx - radius).upto(cx + radius) do |x|
              next if ((x - cx)**2) + ((y - cy)**2) > radius**2

              blend_pixel(x, y, color, alpha)
            end
          end
        end

        def draw_label(text, x:, y:, color:, alpha:, letter_spacing: 0.0)
          chars = text.each_byte.first(24)
          char_width = 14 + Float(letter_spacing).clamp(0.0, 96.0).round
          total_width = chars.length * char_width
          start_x = x.round - total_width / 2
          chars.each_with_index do |byte, index|
            height_factor = 0.35 + (byte % 9) * 0.07
            fill_bar(start_x + index * char_width, y.round, 9, (42 * height_factor).round, color, alpha)
          end
        end

        private

        def fill_bar(x, baseline, bar_width, bar_height, color, alpha)
          (baseline - bar_height).upto(baseline) do |y|
            x.upto(x + bar_width) { |px| blend_pixel(px, y, color, alpha) }
          end
        end

        def blend_pixel(x, y, color, alpha)
          return if x.negative? || y.negative? || x >= width || y >= height

          offset = ((y * width) + x) * 4
          amount = Float(alpha).clamp(0.0, 1.0)
          3.times do |index|
            current = bytes.getbyte(offset + index)
            bytes.setbyte(offset + index, interpolate(current, color[index], amount).round)
          end
          bytes.setbyte(offset + 3, 255)
        end

        def set_pixel(x, y, color, alpha)
          offset = ((y * width) + x) * 4
          bytes.setbyte(offset, color[0])
          bytes.setbyte(offset + 1, color[1])
          bytes.setbyte(offset + 2, color[2])
          bytes.setbyte(offset + 3, alpha)
        end

        def interpolate(from, to, amount)
          from + (to - from) * amount
        end
      end
    end
  end
end
