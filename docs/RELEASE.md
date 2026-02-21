# Release Guide

This guide documents the Phase 5 release flow for `vizcore`.

## 1. Preflight

Run the full verification pipeline:

```bash
bundle exec rake release:verify
```

This runs:

- `bundle exec rspec --exclude-pattern spec/e2e/**/*_spec.rb`
- `rubocop --no-server`
- `npm --prefix frontend test`
- `gem build vizcore.gemspec`
- `ruby scripts/verify_gem_contents.rb`

To include socket-based E2E specs as well:

```bash
bundle exec rake release:preflight_full
```

## 2. Cross-Platform Smoke Confirmation

Before publishing, confirm the latest GitHub Actions run has:

- `cross-platform-smoke` green on:
  - `ubuntu-latest`
  - `macos-latest`
  - `windows-latest`
- `cross-platform-summary` artifact generated

Reference process:

- `docs/CROSS_PLATFORM_TESTING.md`

## 3. Update Release Metadata

- Ensure `lib/vizcore/version.rb` has the target version.
- Update `CHANGELOG.md`:
  - Move release notes from `[Unreleased]` to `[x.y.z] - YYYY-MM-DD`.

## 4. Build and Publish

```bash
gem build vizcore.gemspec
gem push vizcore-<version>.gem
```

`vizcore.gemspec` enforces RubyGems MFA metadata (`rubygems_mfa_required=true`).

Automated path:

- Push tag `v<version>` to trigger `.github/workflows/release.yml`
- Workflow validates tag/version consistency via `scripts/check_release_tag.rb`
- Workflow publishes to RubyGems when `RUBYGEMS_API_KEY` secret is configured

## 5. Post-Release

- Tag release commit (`git tag v<version>`).
- Push tags (`git push --tags`).
- Add release notes in GitHub release page, linking to `CHANGELOG.md`.
