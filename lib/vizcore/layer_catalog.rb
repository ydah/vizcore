# frozen_string_literal: true

module Vizcore
  # Metadata for built-in layer types, params, shaders, and browser effects.
  module LayerCatalog
    Capability = Struct.new(:type, :aliases, :params, :mappable_params, :description, keyword_init: true) do
      def types
        [type, *aliases].map(&:to_sym)
      end

      def supports?(value)
        types.include?(value.to_sym)
      rescue StandardError
        false
      end
    end

    COMMON_PARAMS = {
      opacity: "Float",
      blend: "Symbol",
      effect: "Symbol",
      post_effects: "Array<Symbol>",
      effect_intensity: "Float",
      vj_effect: "Symbol",
      palette: "Array<String>",
      color: "String",
      group: "Symbol"
    }.freeze

    CAPABILITIES = [
      Capability.new(
        type: :geometry,
        aliases: %i[wireframe_cube radial_blob],
        params: COMMON_PARAMS.merge(
          rotation_speed: "Float",
          color_shift: "Float",
          deform: "Array<Float>"
        ),
        mappable_params: %i[rotation_speed color_shift deform],
        description: "Wireframe and radial geometry rendered by the browser."
      ),
      Capability.new(
        type: :shader,
        aliases: [],
        params: COMMON_PARAMS.merge(
          shader_reload: "Boolean",
          param_schema: "Array<Hash>"
        ),
        mappable_params: %i[effect_intensity],
        description: "GLSL ES fragment shader layer with built-in audio uniforms."
      ),
      Capability.new(
        type: :particle_field,
        aliases: %i[particles particle],
        params: COMMON_PARAMS.merge(
          count: "Integer",
          speed: "Float",
          size: "Float",
          force_field: "Symbol",
          turbulence: "Float",
          bass_explosion: "Float",
          sparkle: "Float"
        ),
        mappable_params: %i[speed size turbulence bass_explosion sparkle],
        description: "Audio-reactive point particles with simple force fields."
      ),
      Capability.new(
        type: :text,
        aliases: %i[text_layer],
        params: COMMON_PARAMS.merge(
          content: "String",
          font_size: "Integer",
          letter_spacing: "Float",
          font: "String",
          align: "Symbol",
          stroke_width: "Float",
          stroke_color: "String",
          shadow_color: "String",
          shadow_blur: "Float",
          glow_strength: "Float"
        ),
        mappable_params: %i[font_size letter_spacing glow_strength],
        description: "Canvas text rendered into the WebGL scene."
      ),
      Capability.new(
        type: :svg,
        aliases: %i[svg_layer],
        params: COMMON_PARAMS.merge(
          file: "String",
          src: "String",
          scale: "Float",
          rotation: "Float",
          fit: "Symbol"
        ),
        mappable_params: %i[scale rotation opacity],
        description: "Inline SVG asset rendered as a textured visual layer."
      ),
      Capability.new(
        type: :image,
        aliases: %i[image_layer photo],
        params: COMMON_PARAMS.merge(
          file: "String",
          src: "String",
          scale: "Float",
          rotation: "Float",
          fit: "Symbol"
        ),
        mappable_params: %i[scale rotation opacity],
        description: "Inline PNG/JPEG/GIF/WebP image asset rendered as a textured visual layer."
      ),
      Capability.new(
        type: :video,
        aliases: %i[video_layer footage],
        params: COMMON_PARAMS.merge(
          file: "String",
          src: "String",
          fit: "Symbol",
          scale: "Float",
          rotation: "Float",
          playback_rate: "Float",
          invert: "Float"
        ),
        mappable_params: %i[scale rotation opacity playback_rate invert],
        description: "Inline MP4/WebM/OGV video texture rendered as a looping visual layer."
      ),
      Capability.new(
        type: :waveform,
        aliases: %i[waveform_layer],
        params: COMMON_PARAMS.merge(
          source: "Symbol",
          style: "Symbol",
          height: "Float",
          detail: "Integer"
        ),
        mappable_params: %i[height opacity color_shift],
        description: "Audio feature waveform rendered as line, mirror, or ribbon geometry."
      ),
      Capability.new(
        type: :spectrogram,
        aliases: %i[spectrogram_layer],
        params: COMMON_PARAMS.merge(
          scroll: "Symbol",
          bins: "Integer",
          history: "Integer",
          gain: "Float"
        ),
        mappable_params: %i[gain opacity],
        description: "Scrolling FFT heatmap rendered by the browser."
      ),
      Capability.new(
        type: :shape,
        aliases: %i[shapes shape_layer],
        params: COMMON_PARAMS.merge(
          shapes: "Array<Hash>",
          shape_schema_version: "Integer",
          units: "Symbol",
          color_shift: "Float"
        ),
        mappable_params: %i[color_shift opacity shapes],
        description: "Declarative and Ruby-generated 2D circle, line, rect, polygon, polyline, path, and star primitives rendered by the browser."
      ),
      Capability.new(
        type: :mesh,
        aliases: %i[mesh_layer preset_mesh],
        params: COMMON_PARAMS.merge(
          geometry: "Symbol",
          material: "Symbol",
          scale: "Float",
          deform: "Float",
          color_shift: "Float"
        ),
        mappable_params: %i[scale deform opacity color_shift],
        description: "Preset 3D wireframe meshes: cube, tetrahedron, octahedron, and icosahedron."
      )
    ].freeze

    BUILTIN_SHADERS = %i[
      default gradient_pulse bass_tunnel neon_grid kaleidoscope spectrum_rings
      liquid_wobble audio_bars ruby_crystal starfield waveform_ribbon
      unyo_geometry glitch_flash
    ].freeze

    BLEND_MODES = %i[
      alpha normal add additive multiply screen difference
    ].freeze

    POST_EFFECTS = %i[
      bloom glitch chromatic feedback motion_blur crt
    ].freeze

    VJ_EFFECTS = %i[
      mirror color_shift pixelate
    ].freeze

    module_function

    def capabilities
      (CAPABILITIES + plugin_capabilities).freeze
    end

    def capability_for(type)
      capabilities.find { |capability| capability.supports?(type) }
    end

    def supported_type?(type)
      !!capability_for(type)
    end

    def supported_types
      capabilities.flat_map(&:types).uniq.freeze
    end

    def params_for(type)
      capability_for(type)&.params || {}
    end

    def mappable_params_for(type)
      capability_for(type)&.mappable_params || []
    end

    def register_layer_capability(type:, aliases: [], params: {}, mappable_params: [], description: nil)
      capability = Capability.new(
        type: normalize_type!(type),
        aliases: normalize_symbols(aliases),
        params: COMMON_PARAMS.merge(normalize_param_types(params)),
        mappable_params: normalize_symbols(mappable_params),
        description: normalize_description(description)
      )
      validate_plugin_capability!(capability)
      plugin_capabilities.reject! { |entry| entry.type == capability.type }
      plugin_capabilities << capability
      capability
    end

    def reset_plugin_capabilities!
      plugin_capabilities.clear
    end

    def plugin_capabilities
      @plugin_capabilities ||= []
    end

    def normalize_type!(type)
      value = type.to_s.strip
      raise ArgumentError, "layer capability type must not be empty" if value.empty?

      value.to_sym
    end

    def normalize_symbols(values)
      Array(values).filter_map do |value|
        symbol = value.to_s.strip
        symbol.empty? ? nil : symbol.to_sym
      end.uniq
    end

    def normalize_param_types(params)
      Hash(params).to_h do |name, type|
        [normalize_type!(name), type.to_s]
      end
    end

    def normalize_description(description)
      value = description.to_s.strip
      value.empty? ? "Plugin layer capability." : value
    end

    def validate_plugin_capability!(capability)
      reserved_types = CAPABILITIES.flat_map(&:types)
      conflicts = capability.types & reserved_types
      return if conflicts.empty?

      raise ArgumentError, "layer capability conflicts with built-in type: #{conflicts.first}"
    end
  end
end
