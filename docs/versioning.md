# Versioning

Two version tracks. Do not mix them.

## Tooling (this repo’s Mix app)

| Where | What |
|---|---|
| `mix.exs` → `version` | **Source of truth** for the supporting tooling |
| `CHANGELOG.md` | Human history of tooling changes |
| GitHub Releases / tags | **Optional.** Only use if/when there is an automated bump + release build. Until then, bump `mix.exs` and the changelog; do not hand-tag “product” versions for content |

Bump the Mix version when the Elixir/Surreal tooling or assessment runtime
changes in a way callers care about. Start at **0.x** until the product is
actually shippable.

```
# after a tooling change
# 1. edit mix.exs version
# 2. add a section to CHANGELOG.md
# 3. merge — no GitHub Release required
```

## Content (YAML / Markdown corpus)

Content is **not** versioned via Mix, GitHub tags, or a single “content
release” number.

| Artifact | Field | Meaning |
|---|---|---|
| `frameworks/<id>/<edition>/framework.yaml` | `version` | **Standard edition** (e.g. `"2023"`, `"2024+2026-1744"`). Must match the directory. |
| Requirements | `framework_version` | Same edition as the parent framework directory |
| `questions/*.yaml`, `rubrics/*.yaml`, `templates/*.md` | `version` | **Authored pack revision** for that file (bump when the pack meaningfully changes) |
| Mappings / rulesets | (no pack `version` today) | Editions appear inside ids / `from_framework` / `to_framework` |

History of content edits is **git history** on those paths. When you change a
question pack, bump that file’s `version`. When ISO publishes a new edition,
add a new framework directory — do not overload Mix version for that.

## JSON Schema vs Surreal schema

**Keep `schemas/*.schema.json` for now.** They gate PRs via `mix lint` before
anything touches Surreal.

| Check | JSON Schema + Elixir lint (git) | Surreal SCHEMAFULL |
|---|---|---|
| Required fields / enums / patterns | yes | can mirror later |
| Directory ↔ id / filename rules | Elixir validate | no |
| Cross-file references (mappings, `covers`, …) | Elixir validate | weak / late |
| Charset | `mix isomer.charset` | no |
| Tenant/runtime authz shapes | no | yes (`RuntimeSchema`) |

Surreal as the *only* schema layer would mean invalid corpus can merge and
only fail at sync time, and path/cross-file rules still need Elixir anyway.
Stronger product shape: **git is the authoring system of record for content;
Surreal is the runtime store + tenant schema.** Optional later: add Surreal
field types on corpus tables as defense-in-depth *after* offline lint — not
instead of it.
