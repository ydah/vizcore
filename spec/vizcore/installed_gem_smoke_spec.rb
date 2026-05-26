# frozen_string_literal: true

require "bundler"
require "json"
require "open3"
require "tmpdir"

RSpec.describe "Installed gem smoke" do
  def run_command(*command, env: {})
    stdout, stderr, status = Open3.capture3(env, *command)

    return stdout if status.success?

    raise <<~MSG
      command failed (status #{status.exitstatus}): #{command.shelljoin}
      STDOUT:
      #{stdout}
      STDERR:
      #{stderr}
    MSG
  end

  it "builds, installs, and runs the CLI from a packaged gem" do
    Bundler.with_unbundled_env do
      Dir.mktmpdir("vizcore-installed-gem-smoke") do |tmp_dir|
        gem_file = File.join(tmp_dir, "vizcore.gem")
        installed_exec_name = Gem.win_platform? ? "vizcore.bat" : "vizcore"
        installed_exec = File.join(tmp_dir, "installed-gem", "bin", installed_exec_name)
        run_command(
          Gem.ruby,
          "-S",
          "gem",
          "build",
          "vizcore.gemspec",
          "-o",
          gem_file
        )

        install_root = File.join(tmp_dir, "installed-gem")
        run_command(
          Gem.ruby,
          "-S",
          "gem",
          "install",
          "--local",
          "--ignore-dependencies",
          "--no-document",
          gem_file,
          env: {
            "GEM_HOME" => install_root,
            "GEM_PATH" => [install_root, Gem.path].join(File::PATH_SEPARATOR)
          }
        )

        expect(File).to be_executable(installed_exec)

        features_payload = run_command(
          installed_exec,
          "features",
          "--format",
          "json",
          env: {
            "GEM_HOME" => install_root,
            "GEM_PATH" => [install_root, Gem.path].join(File::PATH_SEPARATOR)
          }
        )

        payload = JSON.parse(features_payload)
        expect(payload).to include("mic", "midi", "ffmpeg", "browser_capture", "fftw")

        validate_output = run_command(
          installed_exec,
          "validate",
          "examples/basic.rb",
          env: {
            "GEM_HOME" => install_root,
            "GEM_PATH" => [install_root, Gem.path].join(File::PATH_SEPARATOR)
          }
        )
        expect(validate_output).to include("Scene valid: examples/basic.rb")
      end
    end
  end
end
