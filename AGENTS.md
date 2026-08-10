# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **YAML/JSON Schema content corpus** (governance content layer) plus SurrealDB tooling and a **Phoenix LiveView** assessment UI in **Elixir / Mix**.

### Core workflow

- Lint: `mix lint` (alias for `mix isomer.validate` + `mix isomer.charset`). See root `README.md`. Pre-commit: `mix setup` / `mix git.hooks` installs `.githooks/pre-commit` (format + compile warnings-as-errors + lint). Manual: `mix precommit`.
- Deps: `mix deps.get` (see `mix.exs` / `mix.lock`). Latest stable Elixir/OTP pinned in `mise.toml` (**1.20.3** / **29.0.5**); required for EEF `sbom` / CycloneDX.
- SurrealDB smoke test: `mix isomer.db.ping` (password from Hashicorp Vault; never commit `.env`).
- **Versioning:** tooling = `mix.exs` (currently **0.1.1**) + **merged PR descriptions** as the human history; content = per-file YAML `version` / framework edition directories — never Mix, and no GitHub Releases for content. Policy: `docs/versioning.md`. No `CHANGELOG.md`. Do not invent “content release” numbers.
- Full corpus→DB sync: `mix isomer.db.sync` (or `--dry-run`). Upserts `domain`, `framework`, `requirement`, `mapping_set`, `ruleset`, `rubric`, `question_set`, `template`; writes `maps_to` graph edges; prunes stale `content_source="repo"` rows; writes a `sync_run` record.
- Sample single-requirement write: `mix isomer.db.ingest_sample`.
- Assessment runtime: `docs/assessment-runtime.md`. Apply Surreal auth + tenant tables with `mix isomer.db.ensure_runtime` (does not prune; separate from corpus sync). CI `sync-corpus.yml` runs **sync then ensure_runtime** on push to `main` / `workflow_dispatch` so new `user` fields (`self_role`, …) and `artifact` land without a manual Mix step. Phoenix LiveViews (`mix phx.server`, `IsomerWeb`) are the projector; Surreal owns identity/session via `DEFINE ACCESS isomer_user`. No Ash / no Ecto user table. Deploy: `docs/deploy.md` (Fly.io or Railway).
- **Fly demo:** app `isomer-demo` → `https://isomer-demo.fly.dev` (`fly.toml`). Web secrets are `SECRET_KEY_BASE`, `PHX_HOST=isomer-demo.fly.dev`, `SURREAL_*` (no Vault on the web dyno). Health check path is `/health`. Deploy on merge to `main` via `.github/workflows/fly-deploy.yml` (needs Actions secret `FLY_API_TOKEN`). After corpus sync, re-run `mix isomer.db.ensure_runtime` so record users can `SELECT` published `question_set` rows. Manual: `fly deploy -a isomer-demo --remote-only`.
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

- `.github/workflows/ci.yml` — `mix deps.get`, compile, format check, `mix lint`, then `mix isomer.sbom` (upload `bom.cdx.json`). Uses Node 24 actions (`actions/cache@v5`, `actions/upload-artifact@v6`). No Surreal dry-run in CI; live sync is separate.
- `.github/workflows/sync-corpus.yml` — on push to `main` (and `workflow_dispatch`), validate then `mix isomer.db.sync`, then `mix isomer.db.ensure_runtime`. Preflight checks that required secrets are non-empty (does not print values). Vault HTTP reads retry on transient failures from runners.
- `.github/workflows/fly-deploy.yml` — on push to `main` (and `workflow_dispatch`), `flyctl deploy -a isomer-demo --remote-only`. Requires Actions secret `FLY_API_TOKEN` (`fly tokens create deploy -a isomer-demo -x 999999h`).
- Required GitHub Actions secrets for live sync: `SURREAL_URL`, `SURREAL_NAMESPACE`, `SURREAL_DATABASE`, `SURREAL_USERNAME`, `VAULT_ADDR`, `VAULT_TOKEN`, `VAULT_SECRET_PATH`, `VAULT_SECRET_FIELD`.
- Secrets are injected into the process environment on the runner (there is usually no `.env` file in CI). Set `DEBUG_SYNC=1` for full stacks on sync failure.

### Web app (`IsomerWeb`)

- Start: `mix phx.server` → `http://localhost:4000` (Bandit). Prod/release needs `PHX_SERVER=true`, `SECRET_KEY_BASE`, `PHX_HOST`, plus `SURREAL_*` for user JWT signup/signin (Vault root password is **not** required on the web request path).
- Signup/signin failures often look quiet in Fly logs: Surreal intentionally returns a generic “record access signup query failed” (e.g. duplicate email). `isomer_user` SIGNUP uses `THROW` for common cases; `SessionController` also `Logger.warning`s auth failures. A failed signup is HTTP **200** re-render of `/login`, not 5xx. Sign-in “No record was returned” means email/password did not match (wrong password is the usual case). Demo recovery: `mix isomer.db.reset_password --email … --password …` (Vault root; Mix-only).
- Sign-in `Mint.TransportError` / `could not connect` / `RPC use timed out` means the Fly dyno could not complete a WSS session to `SURREAL_URL` (Surreal Cloud free tiers pause when idle; also watch connection storms). Not a bad password. `UserClient` retries transient connect failures; LiveView mount / `/login` must **not** clear the session cookie on those timeouts. Confirm Surreal Cloud instance is running, then retry.
- Bare **Forbidden** on `POST /session` is almost always a CSRF race after a successful sign-in (`log_in` renews the session cookie; a second POST still carries the old form token). `IsomerWeb.Plugs.ForgeryProtection` redirects those auth POSTs to `/orgs` when a session token is already present (or back to `/login` with a flash) instead of rendering `ErrorHTML` 403.
- Session cookie stores Surreal user JWT; each LiveView opens its own user-scoped WSS connection via `Isomer.Db.UserClient` and closes it on terminate.
- Org create needs `org` select permission `created_by = $auth.id` (in addition to membership) so `CREATE` can return the row before the `member` edge exists — already in `RuntimeSchema`.
- UI uses Hex `petal_components` + Tailwind v4 / esbuild (`assets/`, aliases `mix assets.setup` / `mix assets.build` / `mix assets.deploy`). Dev watchers rebuild CSS/JS; Docker runs `mix assets.deploy` before release. Deploy: `docs/deploy.md`.
- Assessment lifecycle: org page splits **Ongoing** (`draft`/`in_progress`) vs **Finalized** (`complete`/`archived`). Finalize/Reopen/Delete live on assessment Details; finalized assessments lock wizard edits. Accordion progress counts Yes, No, and unanswered (clear via — + Update). `html` uses `scrollbar-gutter: stable` to avoid layout shift.
- Header **Menu** dropdown is the central nav (Organizations, Library, Settings, Sign out; plus Org dashboard / Assessment / Questionnaire / Artifacts when those assigns are set). Avoid one-off back links as the only way out of the wizard.
- Guidance prefs on `user` (`self_role`, `experience_level`, `comfort_level`) via `/settings`; `Isomer.GuideCopy` adapts wizard/library wording only — same UX for every level. Re-run `mix isomer.db.ensure_runtime` after pulling schema changes.
- Artifacts: generate from corpus `template` on `/assessments/:id/artifacts` (`Isomer.Artifacts.Render` → tenant `artifact` table); catalog + all drafts at `/library`; download Markdown or print-ready HTML (`format=pdf`) via `/artifacts/:id/download`.

### Gotchas

- Run Mix tasks from the **repo root**.
- JSON Schema files declare draft 2020-12; `ex_json_schema` validates via a draft-07 `$schema` rewrite in `Isomer.Schema` (corpus shapes only use shared features).
- YAML `id` is omitted on Surreal upserts (Surreal reserves `id` for the record id); the corpus id is stored as `corpus_id`.
- `rulesets/` may be empty or absent; the validator skips them when no YAML files are present. If any `rubrics/` exist, missing domain rubrics are warnings (filename = domain id).
- Do not put the SurrealDB password in git or in plain `SURREAL_*` env vars for this phase — store it in Vault and point `VAULT_SECRET_*` at it.
- The Surreal Elixir SDK is pulled from GitHub (`surrealdb/surrealdb.elixir`); it is not published on Hex yet.
- Surreal `option<string>` rejects JSON `null` — omit optional fields (e.g. `assessment.ruleset_id`) instead of binding `nil`.
