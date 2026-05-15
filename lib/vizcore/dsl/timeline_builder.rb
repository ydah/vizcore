# frozen_string_literal: true

module Vizcore
  module DSL
    # Collects ordered timeline scene markers and converts them to transitions.
    class TimelineBuilder
      DEFAULT_BEATS_PER_BAR = 4

      Point = Struct.new(:value, :unit, keyword_init: true)

      def initialize(beats_per_bar: DEFAULT_BEATS_PER_BAR)
        @beats_per_bar = positive_integer(beats_per_bar, "beats_per_bar")
        @entries = []
      end

      # Evaluate a timeline block.
      #
      # @yield Timeline marker definitions
      # @return [Vizcore::DSL::TimelineBuilder]
      def evaluate(&block)
        instance_eval(&block) if block
        validate_entries!
        self
      end

      # Add a scene marker at a timeline position.
      #
      # @param position [Numeric, Point] seconds by default, or a value from `seconds`, `beats`, or `bars`
      # @param scene [Symbol, String] scene to activate at the position
      # @return [Hash]
      def at(position, scene:)
        point = normalize_position(position)
        entry = {
          at: point.value,
          unit: point.unit,
          scene: scene.to_sym
        }
        @entries << entry
        entry
      end

      # @param value [Numeric] seconds from the timeline start
      # @return [Point]
      def seconds(value)
        Point.new(value: non_negative_float(value, "timeline seconds"), unit: :seconds)
      end

      # @param value [Numeric] beats from the timeline start
      # @return [Point]
      def beats(value)
        Point.new(value: non_negative_float(value, "timeline beats"), unit: :beats)
      end

      # @param value [Numeric] bars from the timeline start
      # @param beats_per_bar [Integer, nil] meter override
      # @return [Point]
      def bars(value, beats_per_bar: nil)
        beats_per_measure = beats_per_bar.nil? ? @beats_per_bar : positive_integer(beats_per_bar, "beats_per_bar")
        beats(non_negative_float(value, "timeline bars") * beats_per_measure)
      end

      # @return [Array<Hash>] serialized marker definitions
      def to_h
        @entries.map(&:dup)
      end

      # @return [Array<Hash>] generated scene transitions
      def transitions
        @entries.each_cons(2).map do |from_entry, to_entry|
          delta = to_entry.fetch(:at) - from_entry.fetch(:at)
          {
            from: from_entry.fetch(:scene),
            to: to_entry.fetch(:scene),
            trigger: trigger_for(delta, from_entry.fetch(:unit))
          }
        end
      end

      private

      def normalize_position(position)
        return position if position.is_a?(Point)

        seconds(position)
      end

      def trigger_for(delta, unit)
        case unit
        when :seconds
          proc { seconds >= delta }
        when :beats
          proc { beat_count >= delta }
        else
          proc { false }
        end
      end

      def validate_entries!
        return if @entries.length < 2

        unit = @entries.first.fetch(:unit)
        @entries.each_cons(2) do |from_entry, to_entry|
          raise ArgumentError, "timeline entries must use the same unit" unless to_entry.fetch(:unit) == unit

          from_position = from_entry.fetch(:at)
          to_position = to_entry.fetch(:at)
          raise ArgumentError, "timeline positions must increase" unless to_position > from_position
        end
      end

      def non_negative_float(value, name)
        numeric = parse_float(value, name)
        raise ArgumentError, "#{name} must be non-negative" if numeric.negative?

        numeric
      end

      def positive_integer(value, name)
        numeric = parse_integer(value, name)
        raise ArgumentError, "#{name} must be positive" unless numeric.positive?

        numeric
      end

      def parse_float(value, name)
        Float(value)
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{name} must be numeric"
      end

      def parse_integer(value, name)
        Integer(value)
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{name} must be an integer"
      end
    end
  end
end
