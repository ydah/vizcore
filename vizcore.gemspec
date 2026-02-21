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

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "faye-websocket", "~> 0.12"
  spec.add_dependency "puma", "~> 6.0"
  spec.add_dependency "rack", ">= 2.2", "< 4.0"
  spec.add_dependency "thor", "~> 1.3"
end
