# frozen_string_literal: true

require_relative "vizcore/version"
require_relative "vizcore/errors"
require_relative "vizcore/layer_catalog"
require_relative "vizcore/shape"
require_relative "vizcore/dsl"
require_relative "vizcore/analysis"
require_relative "vizcore/audio"
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

  # @param command_available [#call, nil] optional command lookup for tests
  # @return [Hash<Symbol, Boolean>] optional runtime feature availability
  def self.features(command_available: nil)
    command_available ||= method(:command_available?)
    {
      mic: feature_available? { Audio::PortAudioFFI.available? },
      midi: feature_available? { Audio::MidiInput.available? },
      ffmpeg: command_available.call("ffmpeg"),
      browser_capture: root.join("scripts", "browser_capture.mjs").file? && command_available.call("node"),
      fftw: feature_available? { Analysis::FFTProcessor.fftw_available? }
    }
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

  def self.feature_available?
    !!yield
  rescue StandardError
    false
  end
  private_class_method :feature_available?

  def self.command_available?(command)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
      path = File.join(directory, command)
      File.file?(path) && File.executable?(path)
    end
  end
  private_class_method :command_available?
end
