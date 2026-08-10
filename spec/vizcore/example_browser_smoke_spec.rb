# frozen_string_literal: true

require "open3"
require "pathname"
require "tmpdir"

EXAMPLE_BROWSER_SMOKE_REQUIRED = ENV["VIZCORE_BROWSER_SMOKE_REQUIRED"] == "1"
EXAMPLE_BROWSER_FRONTEND_ROOT = File.expand_path("frontend", Dir.pwd)
EXAMPLE_BROWSER_NODE_ENV = begin
  node_modules = File.join(EXAMPLE_BROWSER_FRONTEND_ROOT, "node_modules")
  if File.directory?(node_modules)
    fallback = ENV["NODE_PATH"]
    { "NODE_PATH" => fallback.to_s.empty? ? node_modules : "#{node_modules}#{File::PATH_SEPARATOR}#{fallback}" }
  else
    {}
  end
end

def example_browser_playwright_available?
  _, _, status = Open3.capture3(
    EXAMPLE_BROWSER_NODE_ENV,
    "node",
    "--input-type=module",
    "-e",
    "import('playwright').then(() => process.exit(0)).catch(() => process.exit(1))",
    chdir: EXAMPLE_BROWSER_FRONTEND_ROOT
  )

  status.success?
rescue Errno::ENOENT
  false
end

def example_browser_run(*command)
  stdout, stderr, status = Open3.capture3(EXAMPLE_BROWSER_NODE_ENV, *command)
  return stdout if status.success?

  raise <<~MSG
    command failed (status #{status.exitstatus}): #{command.shelljoin}
    STDOUT:
    #{stdout}
    STDERR:
    #{stderr}
  MSG
end

if !EXAMPLE_BROWSER_SMOKE_REQUIRED
  RSpec.describe "Example scene browser smoke capture" do
    it "skips browser smoke capture unless explicitly enabled" do
      skip("Set VIZCORE_BROWSER_SMOKE_REQUIRED=1 to run example browser smoke capture.")
    end
  end
elsif !example_browser_playwright_available?
  RSpec.describe "Example scene browser smoke capture" do
    it "requires Playwright and browser dependencies to run" do
      raise <<~MSG
        Playwright is required for example browser smoke capture.
        Install with: npm install --prefix frontend (or use the CI task).
      MSG
    end
  end
else
  RSpec.describe "Example scene browser smoke capture" do
    examples = Dir["examples/*.rb"].sort

    examples.each_with_index do |path, index|
      it "captures the first frame for #{path}" do
        Dir.mktmpdir("vizcore-example-browser-smoke") do |tmp_dir|
          out = File.join(tmp_dir, "capture.png")
          example_browser_run(
            Gem.ruby,
            "-Ilib",
            "exe/vizcore",
            "capture",
            path,
            "--host",
            "127.0.0.1",
            "--port",
            (4670 + index).to_s,
            "--audio-source",
            "dummy",
            "--out",
            out,
            "--wait",
            "0",
            "--timeout",
            "12",
            "--width",
            "480",
            "--height",
            "270",
            "--frame-timeout",
            "8000",
            "--trust"
          )

          expect(Pathname.new(out)).to exist
          expect(File.size(out)).to be > 0
        end
      end
    end
  end
end
