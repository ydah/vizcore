# Cross-Platform Testing

This document tracks Phase 5 `5-9` validation for:

- macOS
- Ubuntu
- Windows (WSL2-compatible smoke scope)

## CI Source of Truth

Cross-platform smoke checks are executed by `.github/workflows/main.yml`:

- Job: `cross-platform-smoke` (matrix: `ubuntu-latest`, `macos-latest`, `windows-latest`)
- Smoke command: `bundle exec rspec spec/vizcore_spec.rb`
- Artifact per OS: `cross-platform-smoke-<matrix-os>.json`
- Consolidated artifact: `cross-platform-summary` (`cross-platform-summary.md`)

The summary is also published to the GitHub Actions Step Summary.

## Local Reproduction Commands

```bash
bundle install
bundle exec rspec spec/vizcore_spec.rb
bundle exec rspec
npm --prefix frontend test
```

## Verification Scope

- Ruby runtime boot and gem load
- Core namespace and root-path smoke checks
- Full RSpec and frontend tests are run in dedicated Linux CI jobs (`rspec`, `frontend-test`)

## Notes

- `windows-latest` in GitHub Actions validates Windows runner compatibility for the smoke suite.
- WSL2 runtime behavior should be treated as Ubuntu-compatible for CLI/library-level checks; audio-device specifics require environment-level manual confirmation.
