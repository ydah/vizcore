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
        append_transitions(output, Array(@definition[:transitions]))
        output
      end

      private

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

        values[:kind].to_s
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
    end
  end
end
