# frozen_string_literal: true

require "base64"
require "pathname"

module Vizcore
  module DSL
    # Replaces external layer source paths with browser-ready inline payloads.
    class ShaderSourceResolver
      # @param definition [Hash] DSL definition payload
      # @param scene_file [String, Pathname] source scene file
      # @raise [ArgumentError] when a referenced source file is missing
      # @return [Hash] deep-copied definition with resolved layer source entries
      def resolve(definition:, scene_file:)
        scene_path = Pathname.new(scene_file.to_s).expand_path
        base_dir = scene_path.dirname
        output = deep_dup(definition)
        output[:scenes] = Array(output[:scenes]).map do |scene|
          scene_hash = symbolize_hash(scene)
          scene_hash[:layers] = Array(scene_hash[:layers]).map do |layer|
            resolve_layer(layer, base_dir: base_dir)
          end
          scene_hash
        end
        output
      end

      private

      def resolve_layer(layer, base_dir:)
        layer_hash = symbolize_hash(layer)
        shader_path = layer_hash[:glsl]
        layer_hash = resolve_shader_layer(layer_hash, base_dir: base_dir) if shader_path
        layer_hash = resolve_svg_layer(layer_hash, base_dir: base_dir) if svg_layer?(layer_hash)
        layer_hash
      end

      def resolve_shader_layer(layer_hash, base_dir:)
        shader_path = layer_hash.fetch(:glsl)
        full_path = resolve_path(base_dir: base_dir, shader_path: shader_path)
        raise ArgumentError, "GLSL file not found: #{shader_path}" unless full_path.file?

        layer_hash[:glsl] = shader_path.to_s
        layer_hash[:glsl_source] = full_path.read
        layer_hash
      end

      def resolve_svg_layer(layer_hash, base_dir:)
        params = symbolize_hash(layer_hash[:params] || {})
        svg_path = params[:file]
        return layer_hash unless svg_path

        full_path = resolve_path(base_dir: base_dir, relative_path: svg_path)
        raise ArgumentError, "SVG file not found: #{svg_path}" unless full_path.file?
        raise ArgumentError, "Unsupported SVG file extension: #{svg_path}" unless full_path.extname.downcase == ".svg"

        params[:file] = svg_path.to_s
        params[:src] = "data:image/svg+xml;base64,#{Base64.strict_encode64(full_path.binread)}"
        layer_hash[:params] = params
        layer_hash
      end

      def svg_layer?(layer_hash)
        %i[svg svg_layer].include?(layer_hash[:type]&.to_sym)
      end

      def resolve_path(base_dir:, relative_path: nil, shader_path: nil)
        path = Pathname.new((relative_path || shader_path).to_s)
        return path.expand_path if path.absolute?

        base_dir.join(path).expand_path
      end

      def symbolize_hash(value)
        Hash(value).each_with_object({}) do |(key, entry), output|
          output[key.to_sym] = entry
        end
      rescue StandardError
        {}
      end

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, entry), output|
            output[key] = deep_dup(entry)
          end
        when Array
          value.map { |entry| deep_dup(entry) }
        else
          value
        end
      end
    end
  end
end
