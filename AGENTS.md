# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **YAML/JSON Schema content corpus** (governance content layer) plus early SurrealDB tooling. There is no long-running web app/API to start yet.

### Core workflow

- Lint before sync: `npm run lint` (corpus YAML/schema via `tools/validate.py` + ESLint on `src/`/`scripts/`). See root `README.md`.
- Python deps: `requirements.txt` (`pyyaml`, `jsonschema`). `npm run lint:corpus` runs `tools/ensure_python_deps.py` first so a bare `npm run lint:corpus` works without a manual pip step.
- Node deps: SurrealDB client + dotenv + ESLint. `npm run lint:js` runs `scripts/ensure-node-deps.js` first (auto-`npm install` when eslint is missing) and invokes `node_modules/eslint/bin/eslint.js` directly — do not rely on a global `eslint` on `PATH`. Package scripts live in `package.json`.
- SurrealDB smoke test: `npm run db:ping` (password is read from HashiCorp Vault; never commit `.env`).
- Full corpus→DB sync: `npm run db:sync` (or `npm run db:sync:dry-run`). Upserts `domain`, `framework`, `requirement`, `mapping_set`, `ruleset`, `rubric`; prunes stale `content_source="repo"` rows; writes a `sync_run` record.
- Sample single-requirement write: `npm run db:ingest-sample`.

### SurrealDB + Vault

- Connection helpers: `src/db/connect.js` (`connectSurreal`, `pingSurreal`).
- Sync: `src/db/sync.js` + `src/corpus/load.js`; CLI `scripts/sync-corpus.js`.
- Database params (`DEFINE PARAM`): `src/db/params.js` — e.g. `$isomer_content_source`, `$isomer_maturity_levels`, `$isomer_ai_roles`. Prefer these in SurQL instead of string literals; JS mirrors live in the same module for writers.
- Database functions (`DEFINE FUNCTION`): `src/db/functions.js` — `fn::isomer::*` helpers (`requirement`, `requirements_by_domain`, `applicable_requirements`, `corpus_stats`, `rubric` / `rubric_level`, maturity helpers, graph helpers, etc.). Prefer these for playbook queries.
- Maturity rubrics live in `rubrics/<domain>.yaml` (one per vocab domain, levels L0–L4). Synced to Surreal table `rubric`. Vocab has 13 domains: 9 AIMS-oriented plus 4 ISMS-oriented (`identity-access`, `security-operations`, `physical-environment`, `resilience-continuity`) for ISO/IEC 27001 Annex A.
- Frameworks on disk: `annex-sl-core/1.0` (27 clauses), `iso42001/2023` (38 Annex A controls), `iso27001/2022` (93 Annex A controls). Both standards inherit annex-sl-core; theme/objective headers are not authored as requirements.
- Cross-framework mappings sync as graph edges: `requirement:⟨from⟩ -> maps_to -> requirement:⟨to⟩` with `relation`, `strength`, `note`, `reviewed`, `reviewer` on the edge. Coverage view: `fn::isomer::satisfiers($corpus_id)` (also `maps_to` / `mapped_from`). Mapping-set YAML metadata stays on `mapping_set`; individual rows become `maps_to` edges.
- Vault secret read: `src/vault/secrets.js` (token or AppRole; KV v1/v2).
- Config via `.env` (see `.env.example`). Surreal password comes from Vault (`VAULT_SECRET_PATH` / `VAULT_SECRET_FIELD`), not from a `SURREAL_PASSWORD` env var.
- `VAULT_SECRET_PATH` is the path after `/v1/` (e.g. `kv/data/surreal`). A leading `v1/` is stripped automatically if present.
- Current Surrealist defaults used in this environment: namespace `main`, database `main`, username `admin` (password from Vault).
- If `.env` uses 1Password `op://` references, run `npm run db:ping:op` (requires `op` CLI) instead of `npm run db:ping`.
- Default cloud endpoint is configured in `.env.example`; namespace/database must match what you created in Surrealist.

### CI

- `.github/workflows/ci.yml` — `npm run lint` on PR/push (corpus + JS). No Surreal dry-run in CI; live sync is separate.
- `.github/workflows/sync-corpus.yml` — on push to `main` (and `workflow_dispatch`), validate then `npm run db:sync`.
- Required GitHub Actions secrets for live sync: `SURREAL_URL`, `SURREAL_NAMESPACE`, `SURREAL_DATABASE`, `SURREAL_USERNAME`, `VAULT_ADDR`, `VAULT_TOKEN`, `VAULT_SECRET_PATH`, `VAULT_SECRET_FIELD`.

### Gotchas

- Run the validator and Node scripts from the **repo root**.
- `mappings/` and `rulesets/` may be empty or absent; the validator skips them when no YAML files are present. If any `rubrics/` exist, the validator expects one file per vocab domain (filename = domain id).
- Prefer `npm run lint:corpus` over calling `tools/validate.py` directly so Python deps are ensured. `pip install --user` may place console scripts under `~/.local/bin` (not always on `PATH`).
- Prefer `npm run lint:js` over calling bare `eslint` so Node deps are ensured and the local binary is used.
- Do not put the SurrealDB password in git or in plain `SURREAL_*` env vars for this phase — store it in Vault and point `VAULT_SECRET_*` at it.
