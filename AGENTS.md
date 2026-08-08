# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **YAML/JSON Schema content corpus** (governance content layer), not a long-running web app. There is no database, API server, or frontend to start.

### Core workflow

- Standard commands are in the root `README.md` (Validation section).
- The primary "run" / smoke check is: `python3 tools/validate.py` (exit 0 = clean).
- Dependencies: `pyyaml` and `jsonschema` (Python 3). Install with `pip install pyyaml jsonschema` as documented in the README.
- There is no separate lint/build/dev-server pipeline. Schema + corpus integrity checks live entirely in `tools/validate.py`.

### Gotchas

- Run the validator from the **repo root** so relative paths under `frameworks/`, `schemas/`, `vocab/`, `mappings/`, and `rulesets/` resolve correctly.
- `mappings/` and `rulesets/` may be empty or absent; the validator skips them when no YAML files are present.
- `pip install --user` may place console scripts under `~/.local/bin`; that directory may not be on `PATH`. Prefer `python3 tools/validate.py` over invoking a `jsonschema` CLI shim.
