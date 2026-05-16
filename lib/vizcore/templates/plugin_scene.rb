# frozen_string_literal: true

require_relative "../lib/{{plugin_name}}"

Vizcore.define do
  scene :{{plugin_name}}_demo do
    layer :{{plugin_name}} do
      type :{{plugin_type}}
      intensity 1.0
      fill "#67e8f9"
      blend :add
    end
  end
end
