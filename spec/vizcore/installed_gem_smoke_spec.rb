# frozen_string_literal: true

require "bundler"
require "net/http"
require "json"
require "open3"
require "tmpdir"
require "uri"

RSpec.describe "Installed gem smoke" do
  def installed_env(gem_home)
    {
      "GEM_HOME" => gem_home,
      "GEM_PATH" => [gem_home, Gem.path].join(File::PATH_SEPARATOR)
    }
  end

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

  def run_installed_command(gem_home, *command)
    run_command(*command, env: installed_env(gem_home))
  end

  def run_installed_gem_path(gem_home)
    run_installed_command(
      gem_home,
      Gem.ruby,
      "-e",
      "require 'rubygems'; puts Gem::Specification.find_by_name('vizcore').full_gem_path"
    ).strip
  end

  def installed_gem_files(gem_home)
    gem_path = run_installed_gem_path(gem_home)
    prefix = gem_path + File::SEPARATOR
    Dir.glob(File.join(gem_path, "**", "*")).select { |path| File.file?(path) }.map do |path|
      path.delete_prefix(prefix)
    end
  end

  def source_file_list(pattern)
    Dir.glob(pattern).select { |path| File.file?(path) }.map(&:dup).sort
  end

  def wait_for_http(url, timeout: 8)
    uri = URI(url)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    last_error = nil

    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      begin
        response = Net::HTTP.get_response(uri)
        return response if response.is_a?(Net::HTTPSuccess)
      rescue StandardError => error
        last_error = error
      end
      sleep 0.1
    end

    raise <<~MSG
      Timed out waiting for #{url}
      Last check error: #{last_error}
    MSG
  end

  def with_installed_server(gem_home, installed_exec, example_path, port:)
    pid = Process.spawn(
      installed_env(gem_home),
      installed_exec,
      "start",
      example_path,
      "--audio-source",
      "dummy",
      "--host",
      "127.0.0.1",
      "--port",
      port.to_s,
      "--trust",
      out: File::NULL,
      err: File::NULL
    )

    begin
      yield pid
    ensure
      begin
        Process.kill("TERM", pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end
  end

  it "builds, installs, and runs the CLI from a packaged gem" do
    Bundler.with_unbundled_env do
      Dir.mktmpdir("vizcore-installed-gem-smoke") do |tmp_dir|
        gem_file = File.join(tmp_dir, "vizcore.gem")
        install_root = File.join(tmp_dir, "installed-gem")
        installed_exec_name = Gem.win_platform? ? "vizcore.bat" : "vizcore"
        installed_exec = File.join(install_root, "bin", installed_exec_name)
        run_command(
          Gem.ruby,
          "-S",
          "gem",
          "build",
          "vizcore.gemspec",
          "-o",
          gem_file
        )

        run_command(
          Gem.ruby,
          "-S",
          "gem",
          "install",
          "--local",
          "--ignore-dependencies",
          "--no-document",
          gem_file,
          env: installed_env(install_root)
        )

        expect(File).to be_executable(installed_exec)

        packaged_files = installed_gem_files(install_root).sort
        expect(packaged_files).to include(
          "exe/vizcore",
          "lib/vizcore.rb",
          "frontend/index.html",
          "frontend/src/main.js",
          "examples/basic.rb",
          "examples/assets/complex_demo_loop.wav",
          "scripts/browser_capture.mjs",
          "README.md",
          "LICENSE.txt"
        )
        expect(packaged_files).to include(*source_file_list("frontend/src/**/*"))
        expect(packaged_files).to include(*source_file_list("examples/**/*"))
        expect(packaged_files.grep(%r{\Afrontend/test/})).to be_empty

        features_payload = run_command(
          installed_exec,
          "features",
          "--format",
          "json",
          env: installed_env(install_root)
        )

        payload = JSON.parse(features_payload)
        expect(payload).to include("mic", "midi", "ffmpeg", "browser_capture", "fftw")

        validate_output = run_command(
          installed_exec,
          "validate",
          "examples/basic.rb",
          env: installed_env(install_root)
        )
        expect(validate_output).to include("Scene valid: examples/basic.rb")

        gem_spec_path = run_installed_gem_path(install_root)
        example_path = File.join(gem_spec_path, "examples", "basic.rb")
        port = 4701
        runtime_payload = nil

        with_installed_server(install_root, installed_exec, example_path, port: port) do
          runtime_response = wait_for_http("http://127.0.0.1:#{port}/runtime")
          runtime_payload = JSON.parse(runtime_response.body)

          root_response = run_command(
            Gem.ruby,
            "-Ilib",
            "-e",
            "require 'net/http'; require 'uri'; uri = URI('http://127.0.0.1:#{port}/'); puts Net::HTTP.get(uri)"
          )
          expect(root_response).to include("<html")
        end

        expect(runtime_payload).to include(
          "status" => "ok",
          "audio_source" => "dummy",
          "projector_mode" => false
        )
        expect(runtime_payload.fetch("scene_names")).to include("basic")
      end
    end
  end
end
