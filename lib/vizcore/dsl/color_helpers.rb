# frozen_string_literal: true

module Vizcore
  module DSL
    # Shared color helper methods for Ruby DSL builders.
    module ColorHelpers
      def hsl(hue, saturation, lightness)
        rgb = hsl_to_rgb(Float(hue), Float(saturation), Float(lightness))
        format("#%02x%02x%02x", *rgb)
      rescue ArgumentError, TypeError
        raise ArgumentError, "hsl requires numeric hue, saturation, and lightness"
      end

      def hsv(hue, saturation, value)
        rgb = hsv_to_rgb(Float(hue), Float(saturation), Float(value))
        format("#%02x%02x%02x", *rgb)
      rescue ArgumentError, TypeError
        raise ArgumentError, "hsv requires numeric hue, saturation, and value"
      end

      # Build a reusable gradient descriptor for layer color fields.
      #
      # @param type [Symbol, String] :linear, :radial, or a supported gradient kind
      # @param colors [Array<String>] at least two hex-like color values
      # @param stops [Array<Numeric>, nil] optional stop points in 0.0..1.0
      # @param position [Numeric, nil] optional fixed position in 0.0..1.0
      # @return [Hash]
      def gradient(type: :linear, colors:, stops: nil, position: nil)
        gradient_type = normalize_gradient_type(type)
        normalized_colors = normalize_colors_for_gradient(colors)
        raise ArgumentError, "gradient requires at least two colors" if normalized_colors.length < 2

        stops = normalize_gradient_stops(stops, normalized_colors.length)

        descriptor = {
          type: gradient_type,
          colors: normalized_colors
        }
        descriptor[:stops] = stops if stops
        descriptor[:position] = normalize_gradient_position(position) unless position.nil?
        { gradient: descriptor }
      rescue ArgumentError, TypeError
        raise
      rescue StandardError
        raise ArgumentError, "gradient requires numeric or parseable color values"
      end

      private

      def hsl_to_rgb(hue, saturation, lightness)
        hue = hue % 360.0
        saturation = normalize_percent_value(saturation)
        lightness = normalize_percent_value(lightness)

        return [0, 0, 0] if saturation.zero?

        q = lightness < 0.5 ? lightness * (1.0 + saturation) : lightness + saturation - (lightness * saturation)
        p = 2.0 * lightness - q
        h = hue / 360.0

        [
          hue_channel_to_rgb(h + 1.0 / 3.0, p, q),
          hue_channel_to_rgb(h, p, q),
          hue_channel_to_rgb(h - 1.0 / 3.0, p, q)
        ]
      end

      def hue_channel_to_rgb(value, p, q)
        value += 1.0 while value < 0.0
        value -= 1.0 while value > 1.0

        channel =
          if value < 1.0 / 6.0
            p + (q - p) * 6.0 * value
          elsif value < 1.0 / 2.0
            q
          elsif value < 2.0 / 3.0
            p + (q - p) * (2.0 / 3.0 - value) * 6.0
          else
            p
          end

        (channel * 255.0).round.clamp(0, 255)
      end

      def hsv_to_rgb(hue, saturation, value)
        hue = hue % 360.0
        saturation = normalize_percent_value(saturation)
        value = normalize_percent_value(value)
        return [0, 0, 0] if saturation.zero?

        sector = hue / 60.0
        i = sector.floor.to_i
        f = sector - i
        p = value * (1.0 - saturation)
        q = value * (1.0 - f * saturation)
        t = value * (1.0 - (1.0 - f) * saturation)

        [
          [value, t, p],
          [q, value, p],
          [p, value, t],
          [p, q, value],
          [t, p, value],
          [value, p, q]
        ][i % 6].map { |channel| (channel * 255.0).round.clamp(0, 255) }
      end

      def normalize_percent_value(value)
        normalized = Float(value)
        return normalized / 100.0 if normalized > 1.0

        normalized.clamp(0.0, 1.0)
      end

      def normalize_gradient_type(value)
        symbol = value.to_s.strip.downcase
        raise ArgumentError, "gradient type must be linear or radial" if symbol.empty?

        case symbol
        when "linear", "radial"
          symbol
        else
          raise ArgumentError, "unsupported gradient type: #{value}"
        end
      end

      def normalize_colors_for_gradient(colors)
        values = Array(colors).flatten.map { |color| color.to_s.strip }.reject(&:empty?)
        raise ArgumentError, "gradient requires at least two colors" if values.empty?

        values.each do |value|
          next if value.match?(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/)
          raise ArgumentError, "gradient colors must be hex strings"
        end

        values
      end

      def normalize_gradient_stops(stops, color_count)
        return nil if stops.nil?

        values = Array(stops).map { |value| Float(value) }
        raise ArgumentError, "gradient stops must match color count" if values.length != color_count

        values
      end

      def normalize_gradient_position(value)
        value = Float(value)
        value.clamp(0.0, 1.0)
      end
    end
  end
end
