# frozen_string_literal: true

module Vizcore
  module DSL
    # Reusable layout helper methods for DSL shape point generation.
    module LayoutHelpers
      # Generate a rectangular grid of points.
      #
      # @param count [Integer] total number of points to generate
      # @param columns [Integer, nil] optional grid column count
      # @param rows [Integer, nil] optional grid row count
      # @param spacing [Numeric] spacing used for x/y when axis spacing is omitted
      # @param spacing_x [Numeric, nil] optional override for x spacing
      # @param spacing_y [Numeric, nil] optional override for y spacing
      # @param center [Boolean] whether to center the grid around the origin
      # @param origin [Array<Numeric>] origin point [x, y]
      # @return [Array<Array<Float>>]
      def grid(count:, columns: nil, rows: nil, spacing: 1.0, spacing_x: nil, spacing_y: nil, center: true, origin: [0, 0])
        point_count = normalize_positive_integer(count, :count)

        columns = normalize_positive_integer(columns, :columns) if columns
        rows = normalize_positive_integer(rows, :rows) if rows

        if columns.nil? && rows.nil?
          raise ArgumentError, "grid requires columns or rows"
        end

        columns ||= Float(point_count) / rows.to_f
        rows ||= Float(point_count) / columns.to_f

        columns = columns.ceil
        rows = rows.ceil

        if columns <= 0 || rows <= 0
          raise ArgumentError, "grid columns and rows must be positive"
        end

        x_step = normalize_positive_number(spacing_x || spacing, :spacing_x)
        y_step = normalize_positive_number(spacing_y || spacing, :spacing_y)

        origin_x, origin_y = normalize_xy_pair(origin, :origin)

        x_offset = center && columns > 1 ? -x_step * (columns - 1) / 2.0 : 0.0
        y_offset = center && rows > 1 ? -y_step * (rows - 1) / 2.0 : 0.0

        points = []
        rows.times do |row|
          columns.times do |column|
            break if points.length >= point_count

            points << [
              origin_x + x_offset + (column * x_step),
              origin_y + y_offset + (row * y_step)
            ]
          end
        end

        points
      end

      # Generate points evenly distributed around a circle.
      #
      # @param count [Integer] number of points
      # @param radius [Numeric] circle radius
      # @param start_angle [Numeric] start angle in degrees
      # @param span [Numeric] angular span in degrees
      # @param radius_jitter [Numeric] random jitter applied per-point
      # @param seed [Integer, nil] deterministic jitter seed
      # @param origin [Array<Numeric>] origin point [x, y]
      # @return [Array<Array<Float>>]
      def radial(count:, radius:, start_angle: -90.0, span: 360.0, radius_jitter: 0.0, seed: nil, origin: [0, 0])
        point_count = normalize_positive_integer(count, :count)
        radius = normalize_non_negative_number(radius, :radius)
        span = Float(span)
        start = degrees_to_radians(start_angle)
        jitter = normalize_non_negative_number(radius_jitter, :radius_jitter)
        random = Random.new(Integer(seed || 0))

        origin_x, origin_y = normalize_xy_pair(origin, :origin)

        points = []
        point_count.times do |index|
          ratio = point_count == 1 ? 0.0 : index.to_f / point_count.to_f
          angle = start + (ratio * span) * Math::PI / 180.0
          jitter_amount = jitter.zero? ? 0.0 : (random.rand * 2.0 - 1.0) * jitter
          scaled_radius = radius + jitter_amount
          points << [
            normalize_layout_coordinate(origin_x + Math.cos(angle) * scaled_radius),
            normalize_layout_coordinate(origin_y + Math.sin(angle) * scaled_radius)
          ]
        end

        points
      end

      # Generate spiral points from center outward.
      #
      # @param count [Integer] number of points
      # @param radius [Numeric] outer radius
      # @param turns [Numeric] number of turns
      # @param start_radius [Numeric] inner radius
      # @param start_angle [Numeric] start angle in degrees
      # @param origin [Array<Numeric>] origin point [x, y]
      # @return [Array<Array<Float>>]
      def spiral(count:, radius:, turns: 2.0, start_radius: 0.0, start_angle: -90.0, origin: [0, 0])
        point_count = normalize_positive_integer(count, :count)
        outer_radius = normalize_non_negative_number(radius, :radius)
        start_r = normalize_non_negative_number(start_radius, :start_radius)
        turns = Float(turns)
        start = degrees_to_radians(start_angle)

        if outer_radius < start_r
          raise ArgumentError, "spiral radius must be greater than or equal to start_radius"
        end

        radius_delta = outer_radius - start_r
        full_turns = turns
        origin_x, origin_y = normalize_xy_pair(origin, :origin)

        points = []
        point_count.times do |index|
          ratio = point_count == 1 ? 0.0 : index.to_f / (point_count - 1).to_f
          current_radius = start_r + (radius_delta * ratio)
          angle = start + ratio * full_turns * Math::PI * 2.0
          points << [
            normalize_layout_coordinate(origin_x + Math.cos(angle) * current_radius),
            normalize_layout_coordinate(origin_y + Math.sin(angle) * current_radius)
          ]
        end

        points
      end

      # Generate points packed in concentric rings up to target count.
      #
      # @param count [Integer] target point count
      # @param radius [Numeric] outer packing radius
      # @param min_distance [Numeric, nil] approximate distance between neighboring points
      # @param origin [Array<Numeric>] origin point [x, y]
      # @return [Array<Array<Float>>]
      def circle_pack(count:, radius:, min_distance: nil, origin: [0, 0])
        target_count = normalize_positive_integer(count, :count)
        outer_radius = normalize_non_negative_number(radius, :radius)
        if target_count == 1
          return [normalize_xy_pair(origin, :origin)]
        end

        min_distance = if min_distance.nil?
          outer_radius.to_f / Math.sqrt(target_count)
        else
          normalize_positive_number(min_distance, :min_distance)
        end

        origin_x, origin_y = normalize_xy_pair(origin, :origin)

        points = [ [origin_x, origin_y] ]
        ring = 1
        while points.length < target_count
          ring_radius = min_distance * ring
          break if ring_radius > outer_radius

          ring_capacity = [[(2.0 * Math::PI * ring_radius / min_distance).round, 6].max, 1].max
          per_ring = [ring_capacity, target_count - points.length].min
          angle_step = (Math::PI * 2.0) / per_ring
          0.upto(per_ring - 1) do |index|
            angle = index * angle_step
            points << [
              normalize_layout_coordinate(origin_x + Math.cos(angle) * ring_radius),
              normalize_layout_coordinate(origin_y + Math.sin(angle) * ring_radius)
            ]
            break if points.length >= target_count
          end

          ring += 1
        end

        return points if points.length >= target_count
        raise ArgumentError, "circle_pack cannot place #{target_count} points within radius #{outer_radius}"
      end

      # Generate pseudo-random points inside a box or circle.
      #
      # @param count [Integer] number of points
      # @param width [Numeric, nil] box width
      # @param height [Numeric, nil] box height
      # @param radius [Numeric, nil] circular radius alternative to width/height
      # @param seed [Integer, nil] deterministic random seed
      # @param origin [Array<Numeric>] origin point [x, y]
      # @return [Array<Array<Float>>]
      def scatter(count:, width: nil, height: nil, radius: nil, seed: 0, origin: [0, 0])
        point_count = normalize_positive_integer(count, :count)

        origin_x, origin_y = normalize_xy_pair(origin, :origin)
        random = Random.new(Integer(seed))

        if width.nil? && height.nil? && radius.nil?
          width = 100.0
          height = 100.0
        end

        if radius && !width && !height
          scatter_radius = normalize_non_negative_number(radius, :radius)
          if scatter_radius.zero?
            return Array.new(point_count) { [origin_x, origin_y] }
          end
        elsif width && height
          width = normalize_positive_number(width, :width)
          height = normalize_positive_number(height, :height)
        else
          raise ArgumentError, "scatter requires width and height together, or radius"
        end

        points = []
        point_count.times do
          if radius
            points << sample_scatter_radius(random, scatter_radius, origin_x, origin_y)
          else
            points << [
              origin_x + (random.rand - 0.5) * width,
              origin_y + (random.rand - 0.5) * height
            ]
          end
        end
        points
      end

      private

      def sample_scatter_radius(random, radius, origin_x, origin_y)
        loop do
          x = random.rand * 2.0 - 1.0
          y = random.rand * 2.0 - 1.0
          if x * x + y * y <= 1.0
            return [
              normalize_layout_coordinate(origin_x + x * radius),
              normalize_layout_coordinate(origin_y + y * radius)
            ]
          end
        end
      end

      def normalize_xy_pair(value, name)
        values = Array(value)
        raise ArgumentError, "#{name} must include x and y coordinates" if values.length != 2
        values.map { |part| normalize_numeric(part, name) }
      end

      def normalize_positive_integer(value, name)
        Integer(value).tap do |integer|
          raise ArgumentError, "#{name} must be positive" unless integer > 0
        end
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{name} must be a positive integer"
      end

      def normalize_positive_number(value, name)
        number = Float(value)
        raise ArgumentError, "#{name} must be positive" unless number.positive?
        number
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{name} must be a positive number"
      end

      def normalize_non_negative_number(value, name)
        number = Float(value)
        raise ArgumentError, "#{name} must be zero or more" if number.negative?
        number
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{name} must be a number"
      end

      def normalize_numeric(value, name)
        Float(value)
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{name} must be a number"
      end

      def degrees_to_radians(value)
        Float(value) * (Math::PI / 180.0)
      rescue ArgumentError, TypeError
        raise ArgumentError, "angle must be numeric"
      end

      def normalize_layout_coordinate(value)
        return 0.0 if value.abs < 1e-12
        value
      end
    end
  end
end
