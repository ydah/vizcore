# frozen_string_literal: true

require "json"
require "pathname"
require "time"

reports_root = Pathname.new("cross-platform-reports")
report_files = reports_root.glob("**/cross-platform-smoke-*.json").sort

rows = report_files.map do |path|
  report = JSON.parse(path.read, symbolize_names: true)
  status = report.fetch(:smoke_outcome, "unknown")

  {
    matrix_os: report.fetch(:matrix_os, "unknown"),
    runner_os: report.fetch(:runner_os, "unknown"),
    status: status,
    ruby_version: report.fetch(:ruby_version, "unknown"),
    generated_at: report.fetch(:generated_at, "unknown"),
    run_id: report[:github_run_id],
    sha: report[:github_sha]
  }
end

now = Time.now.utc.iso8601
lines = []
lines << "# Cross-platform Smoke Report"
lines << ""
lines << "- Generated at: `#{now}`"
lines << "- Source: `cross-platform-smoke` matrix job"
lines << ""
lines << "| Matrix OS | Runner OS | Status | Ruby | Generated At | Run ID | SHA |"
lines << "| --- | --- | --- | --- | --- | --- | --- |"

if rows.empty?
  lines << "| (no reports found) | - | - | - | - | - | - |"
else
  rows.each do |row|
    short_sha = row[:sha].to_s[0, 8]
    lines << "| `#{row[:matrix_os]}` | `#{row[:runner_os]}` | `#{row[:status]}` | `#{row[:ruby_version]}` | `#{row[:generated_at]}` | `#{row[:run_id]}` | `#{short_sha}` |"
  end
end

File.write("cross-platform-summary.md", lines.join("\n") + "\n")
