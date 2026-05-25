# frozen_string_literal: true

require "pathname"

module Vizcore
  # Validates browser-side plugin assets before they are served by the runtime.
  class PluginAssetPolicy
    ALLOWED_EXTENSIONS = %w[.js .mjs].freeze

    # @param path [String, Pathname]
    # @param root [String, Pathname, nil] optional sandbox root
    # @return [Pathname]
    def self.validate!(path, root: nil)
      asset_path = Pathname.new(path).expand_path
      root_path = root ? Pathname.new(root).expand_path : nil

      if root_path && !inside_root?(asset_path, root_path)
        raise ArgumentError, "Plugin asset must stay inside #{root_path}: #{asset_path}"
      end

      unless ALLOWED_EXTENSIONS.include?(asset_path.extname.downcase)
        raise ArgumentError, "Unsupported plugin asset extension: #{asset_path.extname}. Use one of: #{ALLOWED_EXTENSIONS.join(', ')}"
      end

      asset_path
    end

    # @param path [Pathname]
    # @param root [Pathname]
    # @return [Boolean]
    def self.inside_root?(path, root)
      relative = path.relative_path_from(root)
      !relative.each_filename.first&.start_with?("..")
    rescue ArgumentError
      false
    end
    private_class_method :inside_root?
  end
end
