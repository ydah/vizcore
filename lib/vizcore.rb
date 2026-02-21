# frozen_string_literal: true

require_relative "vizcore/version"
require "pathname"

module Vizcore
  class Error < StandardError; end

  def self.root
    Pathname.new(__dir__).join("..").expand_path
  end
end
