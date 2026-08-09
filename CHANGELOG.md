# Changelog

Tooling versions only (`mix.exs`). Content is versioned in YAML — see
[`docs/versioning.md`](docs/versioning.md).

## Unreleased

- Fly health check uses `/health` (plain-text liveness) instead of `/login`
- Public discovery: `/robots.txt`, `/llms.txt`, `/humans.txt`,
  `/.well-known/security.txt` (+ `/security.txt`)
- Whole-app type ramp: root `font-size: 112.5%` (18px), body `text-base` + relaxed
  leading; lift cramped `text-xs`/`text-sm` UI copy in wizard, org, and metrics
- `assessment.domain_metrics` is `FLEXIBLE` so SCHEMAFULL accepts dynamic domain-id keys
- Org page: two-column maturity / objective-metrics panels (`lg+`); sparklines for
  Yes %, unanswered, evidence coverage, and logged hours (placeholder until ≥2
  assessments contribute)
- Assessment wizard: per-domain **Collect metrics** opt-in with time scale +
  manual hours; persisted on `assessment.domain_metrics` in Surreal
- GitHub corner gusset ~28% larger; octocat in the corner, label along the edge
  (readable 1rem label)

## 0.1.0 — 2026-08-09

First cut of the Elixir / Surreal supporting stack (pre-product).

- Elixir Mix tooling replaces Python/Node validators and sync scripts
  (`mix lint`, `mix isomer.db.*`, ruleset eval, delta report, charset)
- Surreal over WSS via official Elixir SDK; password from Vault
- CycloneDX SBoM (`mix isomer.sbom`); CI artifact upload
- Toolchain: Elixir **1.20.3** / OTP **29.0.5**
- `decimal ~> 3.1` override + `ex_json_schema ~> 0.11.5`
- Assessment runtime DDL + Surreal record auth (`mix isomer.db.ensure_runtime`);
  LiveView map in `docs/assessment-runtime.md`
- `IsomerWeb` Phoenix LiveViews (session, orgs, assessments, wizard) over Surreal
  user JWT; deploy notes for Fly.io / Railway in `docs/deploy.md`
- README / docs for clear local workflow
