# Roadmap

Working plan to close product and quality gaps in isomer. This is a living
document: update it when a phase ships or scope changes. Tooling version stays
in `mix.exs`; content versions stay in YAML — see [`versioning.md`](versioning.md).

**Architecture constraints (do not regress):**

- SurrealDB is the system of record for identity, tenancy, assessments, answers,
  evidence, and artifacts.
- Phoenix LiveView is the projector (`IsomerWeb`); each LiveView holds a
  **user** JWT, never root/Vault.
- No Ash / no parallel Ecto user table.
- Corpus stays YAML-authored and linted offline (`mix lint`); sync publishes to
  Surreal.

Related design: [`assessment-runtime.md`](assessment-runtime.md),
[`deploy.md`](deploy.md).

---

## Current state (baseline)

| Area | Status |
|---|---|
| Corpus frameworks (Annex SL, ISO 42001, ISO 27001, EU AI Act) | Authored + synced |
| Mappings, one classification ruleset, 13 rubrics, 48 questions, 4 templates | Present; thin for production playbook depth |
| Domain assessments + wizard + finalize/reopen | Live |
| Artifacts from templates | Live (see Phase 0 on storage path) |
| Guidance prefs + adaptive copy | Live (Surreal columns + session fallback) |
| Ruleset/combined assessment UX | Schema ready; UI creates `domains` only |
| Results view | Planned, not routed |
| Evidence upload | Schema ready; LiveView not built; object storage deferred |
| Org member invite / roles UI | Permissions in schema; no management UI |
| Password recovery / SSO | Mix-only reset for demos; no app forgot-password |
| Automated tests in CI | Compile + format + lint + SBoM only — no `mix test` |

---

## Principles

1. **Finish the assessment loop before broadening corpus or adding SSO.**
   Classify → answer → evidence → results → documents.
2. **Ship vertical slices.** Each PR below should be usable alone.
3. **Keep corpus PRs separate from LiveView/runtime PRs.**
4. **Fail closed on Surreal authz.** New write paths need record-auth probes in
   `ensure_runtime` or tagged integration tests.
5. **No calendar estimates.** Scope is measured by subsystems touched and
   dependency depth.

---

## Phase 0 — Stabilize foundations

**Goal:** Reliable green path for feature work; docs match code.

| Work | Detail |
|---|---|
| Artifact storage consistency | Reconcile tenant `artifact` table vs Library fallback via `answer` rows (`pack_ref=__artifacts__`). Prefer one supported path; document any Surreal Cloud DDL workaround explicitly in AGENTS + this file. |
| Test harness | Add `test/support` as referenced by `mix.exs`. ConnCase / LiveView helpers as needed. |
| CI | Run `mix test` after lint in `.github/workflows/ci.yml`. Default suite stays offline (no live Surreal) unless `@tag :surreal`. |
| Smoke coverage seed | Unit tests for `Isomer.Ruleset.Evaluate`, `Isomer.OrgMetrics`, `Isomer.Artifacts.Render`, and pure tenant/helpers with fixtures. |

**Done when:** CI runs compile + format + lint + `mix test`; artifact story is unambiguous in docs.

---

## Phase 1 — Close the assessment loop

Highest product value. Build in order; each sub-phase is shippable.

### 1a. Ruleset assessments in the UI

- Extend `AssessmentLive.New`: choose `domains` / `ruleset` / `combined`; select
  a published corpus ruleset (EU AI Act classification).
- Wizard loads ruleset questions when `ruleset_id` is set.
- On ruleset answer change: run `Isomer.Ruleset.Evaluate` (Elixir; keep as
  reference), then `UPDATE assessment SET classification, activates`.
- SurQL `fn::isomer::evaluate_ruleset` stays deferred (Phase 4).

**Done when:** User can create a ruleset (or combined) assessment, complete
first-match classification, and persist `classification` + `activates`.

### 1b. Results LiveView

- Add `AssessmentLive.Results` at `/assessments/:id/results` (see planned map in
  [`assessment-runtime.md`](assessment-runtime.md)).
- Show classification outcome, activated obligations, and coverage via
  `fn::isomer::satisfiers` (or an Elixir equivalent over synced `maps_to` edges).
- Link from Details / Wizard / Menu when classification exists or the assessment
  is finalized.
- Readable for domain-only runs (maturity / unanswered / evidence coverage)
  even without a ruleset.

**Done when:** Results page is useful for domain-only and ruleset assessments.

### 1c. Evidence (metadata first, then bytes)

- **MVP:** Wizard modal (`EvidenceLive.Upload` or equivalent) to attach evidence
  metadata (`label`, optional URL / `storage_key`, `content_type`) →
  `CREATE evidence` linked to `answer`. List/remove on the question.
- Wire org metrics `evidence_pct` to real `evidence` rows (not only answer
  text fields).
- **Follow-on:** Object storage (S3 / R2 / Fly Tigris): upload binary, store key
  on `evidence.storage_key`; authenticated download controller. Schema fields
  already exist.

**Done when:** Assessors attach and see evidence without leaving the wizard;
metrics count it.

---

## Phase 2 — Multi-user org UX

| Work | Detail |
|---|---|
| Member management | On org show (owner/admin): list members, invite by email (member edge or pending invite), change role, remove. |
| Permission-aware UI | Hide write actions for `viewer`; assessors limited per `RuntimeSchema`. Clear flash on Surreal denials. |
| Password recovery | Prefer Mix-free path: time-limited reset token + email, or keep documenting demo-only `mix isomer.db.reset_password` until email exists. Vault stays off the web dyno. |

**Done when:** A second user can join an org with a role and only sees allowed
actions.

---

## Phase 3 — Content depth

Parallelizable with Phase 2. Mostly YAML; ship in small batches.

1. Expand questions toward fuller L1–L3 coverage per domain (keep practical
   L1/L2 bias; add harder items where rubrics need them).
2. Add templates that close common evidence gaps (e.g. risk register, competence
   matrix, supplier checklist) with valid `covers`.
3. Optional second ruleset or richer EU AI Act pathways if Results exposes gaps.
4. Pack `version` on mappings/rulesets (JSON Schema + validator +
   [`versioning.md`](versioning.md)).
5. Mapping hygiene: gap notes on partial/adjacent edges; review with
   `mix isomer.delta`.

**Done when:** Results + Artifacts feel like a real playbook, not only a demo.

---

## Phase 4 — Hardening and deferred architecture

| Item | Approach |
|---|---|
| SurQL `fn::isomer::evaluate_ruleset` | Port after UI path is stable; Elixir remains reference/oracle in tests. |
| SSO / OIDC | `DEFINE ACCESS … WITH JWT` beside `isomer_user`; no table redesign. |
| `system` table | Per–AI-system scoping for register / impact assessment after org+assessment loop is solid. |
| Real PDF | Optional; browser print → Save as PDF remains acceptable until file delivery is required. |
| Surreal Elixir SDK | Track Hex publish; pin commit SHAs; document vendoring policy. |
| Ops | Fly `SURREAL_*` must match Actions sync target; keep multi-IP `ensure_runtime` probes; document Cloud idle-pause recovery. |

---

## Suggested PR sequence

```text
PR0  Artifact doc/code consistency + test harness + CI mix test
PR1  Ruleset/combined assessment create + wizard eval persistence
PR2  AssessmentLive.Results + nav links
PR3  Evidence metadata modal + tenant CRUD + metrics wiring
PR4  Org members / roles UI
PR5  Evidence object storage (if needed)
PR6+ Content PRs (questions/templates/mappings) in small batches
PR7  Password recovery or SSO (choose from demo vs real-user needs)
```

Do not bundle large corpus expansion with LiveView/runtime changes.

---

## Non-goals (until Phases 1–2 land)

- Phoenix umbrella split or large chrome redesign
- Ash / Ecto user table
- New external frameworks (NIST, SOC 2, …) before the current four are well
  exercised in Results
- Replacing JSON Schema lint with Surreal-only validation

---

## Success criteria

1. User can: sign up → create org → start a **combined** assessment → classify
   under the AI Act → answer domain questions → attach evidence → see results /
   coverage → generate artifacts.
2. A second user can join as assessor or viewer with correct permissions.
3. CI catches regressions with unit tests, not only corpus lint.
4. `assessment-runtime.md`, `AGENTS.md`, and README match routed LiveViews and
   storage reality.

---

## Risks

| Risk | Mitigation |
|---|---|
| Surreal Cloud multi-IP / idle pause looks like auth bugs | Keep `UserClient` retries; `ensure_runtime` multi-pass probes; deploy docs fingerprint check |
| New write paths hit PERMISSIONS surprises | Record-auth probe in ensure_runtime or `@tag :surreal` tests |
| Results UI blocked on thin mappings | Ship Results with fixtures; deepen corpus in Phase 3 |
| Artifact dual-path confusion | Resolve in Phase 0 before Library/evidence work stacks on top |

---

## Tracking

- **This file** is the agreed sequencing for contributors and agents.
- **Linear** (next): one project or initiative mirroring Phases 0–4; issues per
  PR0–PR7 slice above; link issues back here.
- Implementation starts after Linear issues exist for the first slice (Phase 0),
  unless a maintainer explicitly starts without them.
