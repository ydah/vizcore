# frozen_string_literal: true

require_relative "layer_builder"

module Vizcore
  module DSL
    # Collects related layers and applies shared layer parameters.
    class LayerGroupBuilder
      # @param name [Symbol, String] group identifier stored on nested layer params
      # @param styles [Hash] reusable layer parameter styles
      # @param mapping_presets [Hash] reusable layer mapping presets
      # @param defaults [Hash] scene defaults already applied before group params
      # @param strict [Boolean] true when unknown layer params should fail
      def initialize(name:, styles: {}, defaults: {}, mapping_presets: {}, strict: false)
        @name = name.to_sym
        @styles = styles
        @mapping_presets = mapping_presets
        @strict = !!strict
        @params = deep_dup(defaults)
        @layers = []
      end

      # Evaluate a group block.
      #
      # @yield Layer group DSL methods
      # @return [Vizcore::DSL::LayerGroupBuilder]
      def evaluate(&block)
        instance_eval(&block) if block
        self
      end

      # Define one layer in this group.
      #
      # @param name [Symbol, String] layer identifier
      # @yield Layer definition block
      # @return [void]
      def layer(name, &block)
        builder = LayerBuilder.new(name: name, styles: @styles, mapping_presets: @mapping_presets, defaults: layer_defaults, strict: @strict)
        builder.evaluate(&block)
        @layers << builder.to_h
      end

      # @param value [Symbol, String] layer compositing mode shared by nested layers
      # @return [Symbol]
      def blend(value)
        @params[:blend] = value.to_sym
      end

      # Store an ordered color palette shared by nested layers.
      #
      # @param colors [Array<String, Array<String>>] color values such as "#00ffff"
      # @raise [ArgumentError] when no non-blank colors are supplied
      # @return [Array<String>]
      def palette(*colors)
        @params[:palette] = normalize_palette(colors)
      end

      # Merge a named style into this group's shared params.
      #
      # @param name [Symbol, String] style identifier
      # @raise [ArgumentError] when the style is unknown
      # @return [Hash] applied style params
      def use_style(name)
        style_name = name.to_sym
        style_params = @styles.fetch(style_name) { raise ArgumentError, "unknown style: #{style_name}" }
        @params.merge!(deep_dup(style_params))
      end

      # @return [Array<Hash>] serialized nested layers
      def to_a
        @layers.map { |layer| deep_dup(layer) }
      end

      # Stores dynamic one-argument setters into shared group params.
      # @api private
      def method_missing(method_name, *args, &block)
        if block.nil? && args.length == 1
          @params[method_name.to_sym] = args.first
          return args.first
        end

        super
      end

      def respond_to_missing?(method_name, include_private = false)
        @params.key?(method_name.to_sym) || super
      end

      private

      def layer_defaults
        deep_dup(@params).merge(group: @name)
      end

      def normalize_palette(colors)
        values = colors.flatten.map { |color| color.to_s.strip }.reject(&:empty?)
        raise ArgumentError, "group #{@name} palette requires at least one color" if values.empty?

        values
      end

      def deep_dup(value)
        Vizcore::DeepCopy.copy(value)
      end
    end
  end
end
