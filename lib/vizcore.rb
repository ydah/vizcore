# frozen_string_literal: true

require_relative "vizcore/version"
require_relative "vizcore/errors"
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
end
