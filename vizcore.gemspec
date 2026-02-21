# frozen_string_literal: true

require_relative "lib/vizcore/version"

Gem::Specification.new do |spec|
  spec.name = "vizcore"
  spec.version = Vizcore::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "Ruby DSL audio visualizer for DJ/VJ workflows."
  spec.description = "Vizcore provides a Ruby-first workflow to define scenes and render audio-reactive visuals in the browser."
  spec.homepage = "https://github.com/ydah/vizcore"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/README.md"
  spec.metadata["documentation_uri"] = "#{spec.homepage}/blob/main/GETTING_STARTED.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Package only runtime files that are needed after `gem install`:
  # - Ruby runtime and templates (`lib/`)
  # - CLI executable (`exe/`)
  # - Browser runtime assets (`frontend/index.html`, `frontend/src/`)
  # - Example scenes and shader files (`examples/`)
  # - RBS signatures and user docs (`sig/`, README/GETTING_STARTED/LICENSE)
  packaged_prefixes = %w[
    exe/
    lib/
    frontend/index.html
    frontend/src/
    examples/
    sig/
    README.md
    GETTING_STARTED.md
    LICENSE.txt
  ].freeze
  excluded_prefixes = %w[
    frontend/test/
  ].freeze

  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select do |path|
      packaged_prefixes.any? { |prefix| path == prefix || path.start_with?(prefix) }
    end.reject do |path|
      excluded_prefixes.any? { |prefix| path.start_with?(prefix) }
    end
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "faye-websocket", "~> 0.11"
  spec.add_dependency "ffi", "~> 1.17"
  spec.add_dependency "puma", "~> 6.0"
  spec.add_dependency "rack", "~> 2.2.0"
  spec.add_dependency "thor", "~> 1.3"
end
