# Demo Asset Refresh Guide

This document covers demo asset refresh for Phase 5 (`5-11`).

## Current Assets

- `docs/assets/demo.gif` (README embedded animation)
- `docs/assets/demo-poster.png` (static poster)

## Notes

- `docs/assets/demo.gif` is a generated illustrative asset (see `scripts/generate_demo_assets.sh`)
- It is not a direct frame capture of specific runtime scenes
- Use the example scenes in `README.md` for actual local runtime demos

## Local Refresh

Run:

```bash
scripts/generate_demo_assets.sh
```

The script writes:

- `docs/assets/demo.gif`
- `docs/assets/demo-poster.png`

## Validation Checklist

- `README.md` demo image points to `docs/assets/demo.gif`
- `git status` contains updated assets when refreshed
- Demo still renders correctly on GitHub README view
