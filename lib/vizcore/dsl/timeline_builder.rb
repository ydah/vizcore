# frozen_string_literal: true

module Vizcore
  module DSL
    # Collects ordered timeline scene markers and converts them to transitions.
    class TimelineBuilder
      DEFAULT_BEATS_PER_BAR = 4

      Point = Struct.new(:value, :unit, keyword_init: true)

      # @param bpm [Numeric, nil] fixed BPM for mixed-unit timeline conversion
      def initialize(beats_per_bar: DEFAULT_BEATS_PER_BAR, bpm: nil)
        @beats_per_bar = positive_integer(beats_per_bar, "beats_per_bar")
        @entries = []
        @bpm = positive_float(bpm, "timeline bpm") unless bpm.nil?
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
      # @param cue [Symbol, String, nil] optional cue identifier for marker metadata
      # @return [Hash]
      def at(position, scene:, cue: nil)
        point = normalize_position(position)
        entry = {
          at: point.value,
          unit: point.unit,
          scene: scene.to_sym
        }
        entry[:cue] = cue.to_sym if cue
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
        return [] if @entries.length < 2

        @entries.each_cons(2).map do |from_entry, to_entry|
          {
            from: from_entry.fetch(:scene),
            to: to_entry.fetch(:scene),
            trigger: trigger_for(from_entry, to_entry)
          }
        end
      end

      private

      def normalize_position(position)
        return position if position.is_a?(Point)

        seconds(position)
      end

      def trigger_for(from_entry, to_entry)
        return trigger_for_same_unit(from_entry, to_entry) unless mixed_units?(from_entry.fetch(:unit), to_entry.fetch(:unit))

        trigger_for_mixed_units(from_entry, to_entry)
      end

      def trigger_for_same_unit(from_entry, to_entry)
        delta = to_entry.fetch(:at) - from_entry.fetch(:at)
        case from_entry.fetch(:unit)
        when :seconds
          proc { seconds >= delta }
        when :beats
          proc { beat_count >= delta }
        else
          proc { false }
        end
      end

      def trigger_for_mixed_units(from_entry, to_entry)
        fixed_bpm = @bpm

        if fixed_bpm
          from_position = marker_position_seconds(from_entry, fixed_bpm: fixed_bpm)
          to_position = marker_position_seconds(to_entry, fixed_bpm: fixed_bpm)
          if from_position && to_position
            return proc { seconds >= (to_position - from_position) }
          end
        end

        convert_position = lambda do |entry, bpm|
          value = entry.fetch(:at)
          case entry.fetch(:unit)
          when :seconds
            value
          when :beats
            return nil unless bpm.to_f.positive?

            value * 60.0 / Float(bpm)
          else
            nil
          end
        end

        proc do
          used_bpm = fixed_bpm || bpm
          from_position = convert_position.call(from_entry, used_bpm)
          to_position = convert_position.call(to_entry, used_bpm)
          return false unless from_position && to_position

          seconds >= (to_position - from_position)
        end
      end

      def validate_entries!
        return if @entries.length < 2

        @entries.each_cons(2) do |from_entry, to_entry|
          if mixed_units?(from_entry.fetch(:unit), to_entry.fetch(:unit))
            if @bpm
              from_position = marker_position_seconds(from_entry, fixed_bpm: @bpm)
              to_position = marker_position_seconds(to_entry, fixed_bpm: @bpm)
              raise ArgumentError, "timeline entries must increase when converted to seconds" if to_position.nil? || from_position.nil? || to_position <= from_position
            end

            next
          end

          raise ArgumentError, "timeline entries must use the same unit" unless to_entry.fetch(:unit) == from_entry.fetch(:unit)

          from_position = from_entry.fetch(:at)
          to_position = to_entry.fetch(:at)
          raise ArgumentError, "timeline positions must increase" unless to_position > from_position
        end
      end

      def mixed_units?(left_unit, right_unit)
        left_unit != right_unit
      end

      def marker_position_seconds(entry, fixed_bpm:)
        value = entry.fetch(:at)
        case entry.fetch(:unit)
        when :seconds
          value
        when :beats
          return nil unless fixed_bpm.to_f.positive?

          value * 60.0 / Float(fixed_bpm)
        else
          nil
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

      def positive_float(value, name)
        numeric = Float(value)
        raise ArgumentError, "#{name} must be positive" unless numeric.positive?

        numeric
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{name} must be numeric"
      end
    end
  end
end
