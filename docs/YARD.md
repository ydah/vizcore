# YARD API Documentation

Phase 5 task `5-5` uses YARD as the API documentation tool.

## Generate Documentation

```bash
bundle exec rake docs:yard
```

Output directory:

- `doc/yard/`

## Check Undocumented APIs

```bash
bundle exec rake docs:yard_stats
```

This runs:

- `yard stats --list-undoc`

## Configuration

YARD settings are stored in:

- `.yardopts`
