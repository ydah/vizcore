# frozen_string_literal: true

module Vizcore
  module CLISupport
    # Formats loaded scene definitions for CLI inspection.
    class SceneInspector
      def initialize(definition:)
        @definition = definition
      end

      def lines
        output = []
        append_inputs(output, "Audio", Array(@definition[:audio]))
        append_inputs(output, "MIDI", Array(@definition[:midi]))
        append_scenes(output, Array(@definition[:scenes]))
        append_timelines(output, Array(@definition[:timelines]))
        append_transitions(output, Array(@definition[:transitions]))
        append_key_mappings(output, Array(@definition[:key_mappings]))
        output
      end

      def to_h
        sanitize(@definition)
      end

      private

      def sanitize(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, entry), output|
            output[key.to_s] = sanitize(entry)
          end
        when Array
          value.map { |entry| sanitize(entry) }
        when Symbol
          value.to_s
        else
          value.respond_to?(:call) ? true : value
        end
      end

      def append_inputs(output, label, values)
        return if values.empty?

        output << "#{label}:"
        values.each do |input|
          output << "  - #{input[:name]}#{format_options(input[:options])}"
        end
      end

      def append_scenes(output, scenes)
        output << "Scenes:"
        if scenes.empty?
          output << "  (none)"
          return
        end

        scenes.each do |scene|
          output << "  #{scene[:name]}"
          append_layers(output, Array(scene[:layers]))
        end
      end

      def append_layers(output, layers)
        layers.each do |layer|
          output << "    layer #{layer[:name]} (#{format_layer(layer)})"
          Array(layer[:mappings]).each do |mapping|
            output << "      #{format_source(mapping[:source])} -> #{mapping[:target]}#{format_transform(mapping[:transform])}"
          end
        end
      end

      def append_transitions(output, transitions)
        return if transitions.empty?

        output << "Transitions:"
        transitions.each do |transition|
          trigger = transition[:trigger].respond_to?(:call) ? "triggered" : "no trigger"
          output << "  #{transition[:from]} -> #{transition[:to]} (#{trigger})"
        end
      end

      def append_timelines(output, timelines)
        timelines.each_with_index do |timeline, index|
          next if Array(timeline).empty?

          output << "Timeline #{index + 1}:"
          Array(timeline).each do |entry|
            output << "  #{format_timeline_position(entry)} -> #{entry[:scene]}"
          end
        end
      end

      def append_key_mappings(output, mappings)
        return if mappings.empty?

        output << "Keyboard:"
        mappings.each do |mapping|
          output << "  #{mapping[:key]} -> #{format_key_action(mapping[:action])}"
        end
      end

      def format_layer(layer)
        type = layer[:type] || :geometry
        return "#{type}, shader=#{layer[:shader]}" if layer[:shader]
        return "#{type}, glsl=#{layer[:glsl]}" if layer[:glsl]

        type.to_s
      end

      def format_source(source)
        values = Hash(source || {})
        return "unknown" unless values[:kind]
        return "frequency_band(#{values[:band]})" if values[:kind].to_sym == :frequency_band
        return "onset(#{values[:band]})" if values[:kind].to_sym == :onset && values[:band]
        return "global(#{values[:name]})" if values[:kind].to_sym == :global && values[:name]
        return format_lfo_source(values) if values[:kind].to_sym == :lfo

        values[:kind].to_s
      end

      def format_lfo_source(values)
        wave = values[:wave] || :sine
        parts = []
        parts << "rate=#{values[:rate]}" if values.key?(:rate)
        parts << "phase=#{values[:phase]}" if values.key?(:phase)
        suffix = parts.empty? ? "" : ", #{parts.join(', ')}"
        "lfo(#{wave}#{suffix})"
      end

      def format_transform(transform)
        values = Hash(transform || {})
        return "" if values.empty?

        formatted = values.map { |key, value| "#{key}=#{value.inspect}" }.join(", ")
        " [#{formatted}]"
      end

      def format_options(options)
        values = Hash(options || {})
        return "" if values.empty?

        formatted = values.map { |key, value| "#{key}=#{value.inspect}" }.join(", ")
        " (#{formatted})"
      end

      def format_key_action(action)
        values = Hash(action || {})
        case values[:type]&.to_sym
        when :switch_scene
          "switch_scene #{values[:scene]}"
        when :live_control
          options = values.slice(:value, :fade, :release)
          control = values[:control].to_s
          return control if options.empty?

          "#{control}#{format_options(options)}"
        else
          "unknown"
        end
      end

      def format_timeline_position(entry)
        unit = entry[:unit] == :seconds ? "s" : " beats"
        "#{entry[:at]}#{unit}"
      end
    end
  end
end
