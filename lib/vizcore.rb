# frozen_string_literal: true

require_relative "vizcore/version"
require_relative "vizcore/errors"
require_relative "vizcore/layer_catalog"
require_relative "vizcore/shape"
require_relative "vizcore/dsl"
require "pathname"

# Main namespace for the Vizcore runtime and DSL entrypoints.
module Vizcore
  # Base exception for Vizcore runtime failures.
  class Error < StandardError; end
  # Raised when an optional external dependency is required but unavailable.
  class MissingDependencyError < Error; end

  # @return [Pathname] absolute root path for this gem source tree.
  def self.root
    Pathname.new(__dir__).join("..").expand_path
  end

  # @return [Pathname] absolute path to bundled frontend assets.
  def self.frontend_root
    root.join("frontend")
  end

  # @return [Pathname] absolute path to scaffold template files.
  def self.templates_root
    root.join("lib", "vizcore", "templates")
  end

  # Evaluate a Vizcore DSL definition block.
  #
  # @yield DSL configuration block (`audio`, `scene`, `midi_map`, etc.)
  # @return [Hash] serialized DSL definition
  def self.define(&block)
    DSL::Engine.define(&block)
  end

  # Load a Vizcore plugin by Ruby require path.
  #
  # @param name [String, Symbol] require path for the plugin
  # @return [true]
  def self.plugin(name)
    require name.to_s
  end

  # Register a plugin-provided layer capability for validation and docs.
  #
  # @param type [Symbol, String] primary layer type
  # @param aliases [Array<Symbol, String>] supported aliases
  # @param params [Hash] layer parameter metadata
  # @param mappable_params [Array<Symbol, String>] params that can be mapped
  # @param description [String, nil] human-readable docs text
  # @return [Vizcore::LayerCatalog::Capability]
  def self.register_layer_capability(type:, aliases: [], params: {}, mappable_params: [], description: nil)
    LayerCatalog.register_layer_capability(
      type: type,
      aliases: aliases,
      params: params,
      mappable_params: mappable_params,
      description: description
    )
  end
end
