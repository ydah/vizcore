# frozen_string_literal: true

require_relative "png_writer"

module Vizcore
  module Renderer
    # Renders a deterministic software preview PNG from a scene frame.
    class SnapshotRenderer
      DEFAULT_WIDTH = 1280
      DEFAULT_HEIGHT = 720
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
