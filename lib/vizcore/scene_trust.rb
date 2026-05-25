# frozen_string_literal: true

require "pathname"

module Vizcore
  # Builds safety warnings for Ruby scene files, which execute as normal Ruby.
  module SceneTrust
    module_function

    # @param scene_file [String, Pathname, nil]
    # @param project_root [String, Pathname]
    # @return [String, nil]
    def warning_for(scene_file, project_root: Dir.pwd)
      return nil if scene_file.to_s.strip.empty?

      path = Pathname.new(scene_file).expand_path
      root = Pathname.new(project_root).expand_path
      return nil if under?(path, root)
      return nil if under?(path, Vizcore.root)

      "Scene files execute Ruby code. Review #{path} before running it, or pass --trust to suppress this warning."
    end

    def under?(path, root)
      relative = path.relative_path_from(root)
      !relative.each_filename.first&.start_with?("..")
    rescue ArgumentError
      false
    end
  end
end
