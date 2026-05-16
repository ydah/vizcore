# frozen_string_literal: true

require "vizcore"

module {{plugin_module}}
  LAYER_TYPE = :{{plugin_type}}

  Vizcore.register_layer_capability(
    type: LAYER_TYPE,
    aliases: [:{{plugin_name}}],
    params: {
      intensity: "Float",
      color: "CSS color",
      blend: "Blend mode",
      opacity: "Float"
    },
    mappable_params: %i[intensity opacity],
    description: "{{plugin_title}} browser-rendered plugin layer."
  )
end
