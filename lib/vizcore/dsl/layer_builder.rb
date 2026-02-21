# frozen_string_literal: true

module Vizcore
  module DSL
    class LayerBuilder
      def initialize(name:)
        @name = name.to_sym
        @type = nil
        @shader = nil
        @glsl = nil
        @params = {}
        @mappings = []
      end

      def evaluate(&block)
        instance_eval(&block) if block
        self
      end

      def type(value)
        @type = value.to_sym
      end

      def shader(value)
        @shader = value.to_sym
        @type ||= :shader
      end

      def glsl(path)
        @glsl = path.to_s
        @type ||= :shader
      end

      def count(value)
        @params[:count] = Integer(value)
      end

      def content(value)
        @params[:content] = value.to_s
      end

      def font_size(value)
        @params[:font_size] = Integer(value)
      end

      def map(definition)
        mapping = Hash(definition)
        raise ArgumentError, "map requires at least one mapping pair" if mapping.empty?

        mapping.each do |source, target|
          @mappings << {
            source: normalize_source(source),
            target: target.to_sym
          }
        end
      end

      def amplitude
        source(:amplitude)
      end

      def frequency_band(name)
        source(:frequency_band, band: name.to_sym)
      end

      def fft_spectrum
        source(:fft_spectrum)
      end

      def beat?
        source(:beat)
      end

      def beat_count
        source(:beat_count)
      end

      def bpm
        source(:bpm)
      end

      def to_h
        layer = {
          name: @name,
          type: resolved_type,
          params: @params.dup
        }
        layer[:shader] = @shader if @shader
        layer[:glsl] = @glsl if @glsl
        layer[:mappings] = @mappings.map { |mapping| mapping.dup } unless @mappings.empty?
        layer
      end

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

      def resolved_type
        return @type if @type
        return :shader if @shader || @glsl

        :geometry
      end

      def normalize_source(source_value)
        case source_value
        when Hash
          kind = source_value[:kind] || source_value["kind"]
          raise ArgumentError, "mapping source hash must contain :kind" unless kind

          source(kind.to_sym, **normalize_source_options(source_value))
        when Symbol
          source(source_value)
        when String
          source(source_value.to_sym)
        else
          raise ArgumentError, "unsupported mapping source: #{source_value.inspect}"
        end
      end

      def normalize_source_options(source_value)
        source_value.each_with_object({}) do |(key, value), options|
          symbol_key = key.to_sym
          next if symbol_key == :kind

          options[symbol_key] = value.respond_to?(:to_sym) ? value.to_sym : value
        end
      end

      def source(kind, **options)
        {
          kind: kind.to_sym,
          **options
        }
      end
    end
  end
end
