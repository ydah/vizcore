# frozen_string_literal: true

require "json"
require "time"

matrix_os = ENV.fetch("MATRIX_OS", "unknown")
report_path = "cross-platform-smoke-#{matrix_os}.json"

report = {
  generated_at: Time.now.utc.iso8601,
  matrix_os: matrix_os,
  runner_os: ENV.fetch("RUNNER_OS", "unknown"),
  smoke_outcome: ENV.fetch("SMOKE_OUTCOME", "unknown"),
  smoke_conclusion: ENV.fetch("SMOKE_CONCLUSION", "unknown"),
  ruby_version: RUBY_VERSION,
  github_run_id: ENV["GITHUB_RUN_ID"],
  github_run_attempt: ENV["GITHUB_RUN_ATTEMPT"],
  github_sha: ENV["GITHUB_SHA"]
}

File.write(report_path, JSON.pretty_generate(report))
