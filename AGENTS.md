# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **YAML/JSON Schema content corpus** (governance content layer) plus SurrealDB tooling in **Elixir / Mix**. There is no long-running web app/API to start yet.

### Core workflow

- Lint: `mix lint` (alias for `mix isomer.validate` + `mix isomer.charset`). See root `README.md`.
- Deps: `mix deps.get` (see `mix.exs` / `mix.lock`). Elixir **1.19.4** / OTP **27.3.4** pinned in `mise.toml` (needed for EEF `sbom` / CycloneDX).
- SurrealDB smoke test: `mix isomer.db.ping` (password from Hashicorp Vault; never commit `.env`).
- Content release **1.0.0** (`CHANGELOG.md`, `mix.exs` version). Full corpus→DB sync: `mix isomer.db.sync` (or `--dry-run`). Upserts `domain`, `framework`, `requirement`, `mapping_set`, `ruleset`, `rubric`, `question_set`, `template`; writes `maps_to` graph edges; prunes stale `content_source="repo"` rows; writes a `sync_run` record.
- Sample single-requirement write: `mix isomer.db.ingest_sample`.
- CycloneDX SBoM: `mix isomer.sbom` (alias `mix sbom`) → `bom.cdx.json` via Hex package `sbom` (`only: :dev`). Do not run under `MIX_ENV=prod`. CI uploads the JSON as an artifact.

### SurrealDB + Vault

- Connection: `lib/isomer/db/connect.ex` (`Isomer.Db.Connect`) — official `surrealdb` Elixir SDK over **WSS**.
- Sync: `lib/isomer/db/sync.ex` + `lib/isomer/corpus/load.ex`; Mix task `mix isomer.db.sync`.
- Database params (`DEFINE PARAM`): `lib/isomer/db/params.ex` — e.g. `$isomer_content_source`, `$isomer_maturity_levels`, `$isomer_ai_roles`. Prefer these in SurQL instead of string literals.
- Database functions (`DEFINE FUNCTION`): `lib/isomer/db/functions.ex` — `fn::isomer::*` helpers (`requirement`, `requirements_by_domain`, `applicable_requirements`, `corpus_stats`, `rubric` / `rubric_level`, maturity helpers, graph helpers, etc.). Prefer these for playbook queries.
- Maturity rubrics live in `rubrics/<domain>.yaml` (one per vocab domain, levels L0–L4). Synced to Surreal table `rubric`. Vocab has 13 domains: 9 AIMS-oriented plus 4 ISMS-oriented (`identity-access`, `security-operations`, `physical-environment`, `resilience-continuity`) for ISO/IEC 27001 Annex A.
- Frameworks on disk: `annex-sl-core/1.0` (27 clauses), `iso42001/2023` (38 Annex A controls), `iso27001/2022` (93 Annex A controls), `eu-ai-act/2024+2026-1744` (18 obligations). ISO standards inherit annex-sl-core; theme/objective headers are not authored as requirements.
- Classification rulesets: `rulesets/eu-ai-act-classification.yaml`. Evaluate with `mix isomer.ruleset.eval` — **first-match** on `outcomes[]` (order is semantic). Outcome `applicable_from` overrides requirement-level dates for activated obligations (Annex III vs Annex I pathways). See README Conventions.
- Cross-framework mappings sync as graph edges: `requirement:⟨from⟩ -> maps_to -> requirement:⟨to⟩` with `relation`, `strength`, `note`, `reviewed`, `reviewer` on the edge. Coverage view: `fn::isomer::satisfiers($corpus_id)` (also `maps_to` / `mapped_from`). Mapping-set YAML metadata stays on `mapping_set`; individual rows become `maps_to` edges. Per-edge `from_framework` / `to_framework` are derived from requirement ids so one mapping set can target multiple namespaces (AI Act → AIMS edges hit both `iso42001/2023` and `annex-sl-core/1.0`).
- Mapping sets: `mappings/iso42001-2023--iso27001-2022.yaml` (ISMS→AIMS) and `mappings/eu-ai-act-2024-2026-1744--iso42001-2023.yaml` (AIMS→AI Act). `mix isomer.delta PATH` for coverage buckets. Validator normalizes YAML dates so `reviewed` schema-checks as ISO strings; also validates `questions/` + `templates/` (`covers` / `requirements` resolve; unused merge fields warn). `mix lint` also runs charset checks (rejects non-Latin letters / CJK leakage; allows em dashes etc.).
- Questions: `questions/<domain>.yaml` (48 L1/L2-weighted; cross-framework `requirements[]`). Templates: `templates/tmpl-*.md` with `covers` frontmatter. Synced as `question_set` / `template` tables.
- Vault secret read: `lib/isomer/vault/secrets.ex` (token or AppRole; KV v1/v2; retries on transient HTTP failures).
- Config via `.env` (see `.env.example`). `SURREAL_URL` is required and must not be committed — use local `.env`, 1Password `op://`, or the GitHub Actions secret. Surreal password comes from Vault (`VAULT_SECRET_PATH` / `VAULT_SECRET_FIELD`), not from a `SURREAL_PASSWORD` env var.
- `VAULT_SECRET_PATH` is the path after `/v1/` (e.g. `kv/data/surreal`). A leading `v1/` is stripped automatically if present.
- Typical Surrealist defaults in this environment: namespace `main`, database `main`, username `admin` (password from Vault). Namespace/database must match what you created in Surrealist.
- If `.env` uses 1Password `op://` references, run via `op run --env-file=.env -- mix isomer.db.ping` (requires `op` CLI).

### CI

- `.github/workflows/ci.yml` — `mix deps.get`, compile, format check, `mix lint`, then `mix isomer.sbom` (upload `bom.cdx.json`). No Surreal dry-run in CI; live sync is separate.
- `.github/workflows/sync-corpus.yml` — on push to `main` (and `workflow_dispatch`), validate then `mix isomer.db.sync`. Preflight checks that required secrets are non-empty (does not print values). Vault HTTP reads retry on transient failures from runners.
- Required GitHub Actions secrets for live sync: `SURREAL_URL`, `SURREAL_NAMESPACE`, `SURREAL_DATABASE`, `SURREAL_USERNAME`, `VAULT_ADDR`, `VAULT_TOKEN`, `VAULT_SECRET_PATH`, `VAULT_SECRET_FIELD`.
- Secrets are injected into the process environment on the runner (there is usually no `.env` file in CI). Set `DEBUG_SYNC=1` for full stacks on sync failure.

### Gotchas

- Run Mix tasks from the **repo root**.
- JSON Schema files declare draft 2020-12; `ex_json_schema` validates via a draft-07 `$schema` rewrite in `Isomer.Schema` (corpus shapes only use shared features).
- YAML `id` is omitted on Surreal upserts (Surreal reserves `id` for the record id); the corpus id is stored as `corpus_id`.
- `rulesets/` may be empty or absent; the validator skips them when no YAML files are present. If any `rubrics/` exist, missing domain rubrics are warnings (filename = domain id).
- Do not put the SurrealDB password in git or in plain `SURREAL_*` env vars for this phase — store it in Vault and point `VAULT_SECRET_*` at it.
- The Surreal Elixir SDK is pulled from GitHub (`surrealdb/surrealdb.elixir`); it is not published on Hex yet.
