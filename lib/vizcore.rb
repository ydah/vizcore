# frozen_string_literal: true

require_relative "vizcore/version"
require_relative "vizcore/dsl"
require "pathname"

module Vizcore
  class Error < StandardError; end
  class MissingDependencyError < Error; end

  def self.root
    Pathname.new(__dir__).join("..").expand_path
  end

  def self.frontend_root
    root.join("frontend")
  end

  def self.templates_root
    root.join("lib", "vizcore", "templates")
  end

  def self.define(&block)
    DSL::Engine.define(&block)
  end
end
