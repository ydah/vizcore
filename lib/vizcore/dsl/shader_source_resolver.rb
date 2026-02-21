# frozen_string_literal: true

require "pathname"

module Vizcore
  module DSL
    class ShaderSourceResolver
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
        return layer_hash unless shader_path

        full_path = resolve_path(base_dir: base_dir, shader_path: shader_path)
        raise ArgumentError, "GLSL file not found: #{shader_path}" unless full_path.file?

        layer_hash[:glsl] = shader_path.to_s
        layer_hash[:glsl_source] = full_path.read
        layer_hash
      end

      def resolve_path(base_dir:, shader_path:)
        path = Pathname.new(shader_path.to_s)
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
