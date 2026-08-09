# Changelog

Tooling versions only (`mix.exs`). Content is versioned in YAML — see
[`docs/versioning.md`](docs/versioning.md).

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
- README / docs for clear local workflow
