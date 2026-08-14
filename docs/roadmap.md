# Roadmap

isomer is a shared AI governance content layer and assessment runtime: requirements,
cross-framework mappings, maturity questions, classification rules, and document
templates—authored in git, published to SurrealDB, and projected through Phoenix
LiveView.

This roadmap defines what we build next so an organization can **classify
obligations, assess maturity, attach evidence, understand residual work, and
produce governance artifacts** in one coherent loop. Update the document when a
milestone ships or priorities change.

Design references: [`assessment-runtime.md`](assessment-runtime.md),
[`versioning.md`](versioning.md), [`deploy.md`](deploy.md).

---

## Product outcome

An assessor (or small governance team) should be able to:

1. Establish an organization and invite collaborators with appropriate roles.
2. Run an assessment that combines **regulatory classification** (e.g. EU AI Act)
   with **domain maturity** questions grounded in the published corpus.
3. Record answers and link supporting evidence to those answers.
4. See **what applies**, **what is covered by existing controls/mappings**, and
   **what remains**—not only a questionnaire progress bar.
5. Generate starting documents (policy, SoA, impact assessment, …) from corpus
   templates bound to the assessment.

Content remains the source of truth in YAML; the app never invents requirements
at runtime. Surreal owns identity, tenancy, and assessment data; LiveView never
holds root/Vault credentials.

---

## What is already in place

| Capability | Notes |
|---|---|
| Governance corpus | Annex SL core, ISO/IEC 42001:2023, ISO/IEC 27001:2022, EU AI Act (`2024+2026-1744`), with evidence expectations on requirements |
| Crosswalks | ISMS↔AIMS and AIMS↔AI Act mapping sets, synced as `maps_to` graph edges |
| Classification | EU AI Act ruleset with first-match evaluation; UI create + wizard persist; Results shows residual coverage via `maps_to` satisfiers (Themes 2.1–2.2) |
| Maturity model | 13 domain rubrics (L0–L4) and aligned question packs |
| Assessment UX | Org tenancy with member admin + role-aware projector; domain / ruleset / combined assessments; wizard with evidence; Results; finalize/reopen; adaptive guidance copy |
| Documents | Template render → Library downloads (Markdown / print-ready HTML); stored as `answer` rows (`pack_ref=__artifacts__`) |
| Tooling SBoM | CycloneDX published to Surreal `sbom:isomer_tooling` on sync (`mix isomer.db.sync_sbom`) |
| Delivery | Corpus sync + runtime schema + SBoM sync in CI; Fly demo deploy on `main`; `mix test` in CI |

Remaining Theme 2 work is done for the assessment loop (slice F object storage
shipped). Theme 3 member admin + org polish shipped; password recovery remains
slice H. Content depth (Theme 4) can proceed in parallel.

---

## Architecture invariants

These are not open questions:

- SurrealDB is the system of record for users, orgs, assessments, answers,
  evidence, and artifacts.
- `IsomerWeb` is a projector: user JWT over WSS per LiveView; Mix/Vault remain
  for corpus sync and schema ensure only.
- No parallel application user store (no Ash, no Ecto accounts table).
- Corpus shape is enforced by JSON Schema + `mix lint` before sync.
- Content editions and tooling versions stay on separate tracks
  ([`versioning.md`](versioning.md)).

---

## Themes and sequencing

Work is ordered by dependency: a trustworthy assessment loop first, then
collaboration, then corpus breadth, then platform hardening. Implementation may
overlap where noted; corpus authoring can proceed in parallel once Results
exists to exercise mappings.

```text
Foundation → Assessment completeness → Collaboration → Content depth → Platform
```

### 1. Foundation integrity — shipped

**Status:** Complete (merged PR #64).

| Deliverable | Acceptance |
|---|---|
| Single supported artifact persistence model | Library and assessment document flows use answer-backed storage (`pack_ref=__artifacts__`); standalone `artifact` table is DEFINE/forward-only; documented in AGENTS + assessment-runtime |
| Test harness + CI execution | `mix test` runs in CI after lint; `test/support` matches `mix.exs`; default suite does not require a live Surreal instance |
| Core pure-logic coverage | Ruleset evaluation, org metrics, and template render have fixture-based unit tests |

### 2. Assessment completeness

**Intent:** Complete classify → answer → evidence → residual work → documents
without leaving the product.

#### 2.1 Regulatory classification in the assessment UI — shipped

**Status:** Complete in this iteration (create + wizard + Details summary).

- Assessment create supports `domains`, `ruleset`, and `combined`.
- Wizard presents ruleset questions when `ruleset_id` is set (`pack: "ruleset"`).
- Answers trigger `Isomer.Ruleset.Evaluate` and persist `classification` and
  `activates` on the assessment.
- Details shows ruleset id, outcome label, and activated obligation count.

**Acceptance:** A combined assessment can determine applicable AI Act obligations
and retain that outcome for later views and artifact context.

#### 2.2 Results and residual work — shipped

**Status:** Complete in this iteration (`AssessmentLive.Results` + chrome links).

Add `AssessmentLive.Results` (`/assessments/:id/results`):

- Classification summary and activated obligations when present.
- Coverage / residual view using `fn::isomer::satisfiers` (or equivalent over
  synced `maps_to` edges).
- Domain-only assessments still get a clear maturity and completion picture.

**Acceptance:** Finalized and in-progress assessments both have a results view
that answers “what applies?” and “what is still open?”—linked from assessment
chrome (Details, Wizard, Menu).

#### 2.3 Evidence on answers — shipped (metadata + object storage)

**Status:** Complete for metadata attach/list/remove + metrics + object storage.

Schema for `evidence` exists; the wizard attaches and lists it.

- First slice: metadata (label, content type, URL or storage key) created under
  the answer, with remove; org metrics `evidence_pct` reflects real evidence
  rows. **Shipped.**
- Second slice: object storage for binaries (`memory` / `local` / S3-compatible),
  wizard file upload, authenticated download at `/evidence/:id/download`,
  `storage_key` populated end-to-end. **Shipped (slice F).**

**Acceptance:** Assessors can support answers with evidence in-flow; coverage
metrics include evidence, not only Yes/No counts.

### 3. Collaboration — members shipped; recovery pending

**Intent:** Assessments are team work. Roles already exist on `member`
(`owner` / `admin` / `assessor` / `viewer`); the UI must manage and respect them.

| Deliverable | Acceptance |
|---|---|
| Member administration | Owners/admins list members, invite by email (existing accounts), change roles, remove access — **shipped** |
| Authorization in the projector | Write actions hidden or blocked for viewers; Surreal denials surface as clear errors — **shipped** |
| Account recovery | Password reset usable without operator Mix/Vault on the web path (token + email, or equivalent); web dyno still never needs Vault for auth — **pending (slice H)** |

Org dashboard polish landed with member admin: assessments primary, richer
assessment rows, stronger empty state, maturity/metrics visible on load
(collapsible). Members live on `/orgs/:org_id/members`.

### 4. Content depth

**Intent:** The runtime is only as useful as the playbook. Deepen the corpus
against the Results and evidence flows—not as an unbounded content dump.

Priority order:

1. Question packs: stronger L1–L3 coverage per domain where rubrics imply gaps.
2. Templates that match common evidence expectations (risk register, competence
   records, supplier due diligence, etc.) with valid `covers`.
3. Classification and mapping fidelity: richer AI Act pathways where Results
   shows weak activation or coverage; gap notes on partial/adjacent mappings;
   pack `version` on mappings and rulesets per [`versioning.md`](versioning.md).

Review mappings with `mix isomer.delta`. Keep content PRs small and separate
from runtime changes.

**Acceptance:** For the supported frameworks, Results and generated documents
are substantive enough for internal governance use—not a skeleton questionnaire.

### 5. Platform and enterprise readiness

After the loop and collaboration paths are solid:

| Item | Direction |
|---|---|
| In-database ruleset evaluation | `fn::isomer::evaluate_ruleset` in SurQL; Elixir evaluator remains the test oracle |
| SSO / OIDC | Additional Surreal `DEFINE ACCESS … WITH JWT` alongside record auth; no second user table |
| AI system register | `system` (or equivalent) for per–AI-system scoping of assessments and artifacts |
| Document export | Native PDF only if browser print/HTML is insufficient for stakeholders |
| Dependency posture | Pin/track the Surreal Elixir client; document upgrade policy while it remains GitHub-sourced |
| Operations | Actions sync target and Fly `SURREAL_*` stay identical; retain multi-pass `ensure_runtime` probes for Surreal Cloud |

---

## Delivery slices

Prefer vertical, reviewable changes. Suggested order:

| Slice | Scope | Status |
|---|---|---|
| A | Artifact model clarity + test harness + CI `mix test` (+ SBoM→Surreal) | Shipped (#64) |
| B | Ruleset / combined assessment create + wizard persistence of classification | Shipped (#66) |
| C | Results LiveView + navigation | Shipped (#68) |
| D | Evidence metadata in wizard + metrics | Shipped (#69) |
| E | Org member administration + role-aware UI (+ org polish) | Shipped (this work) |
| F | Evidence object storage | Shipped (this work) |
| G | Content batches (questions, templates, mappings) | Next |
| H | Password recovery and/or SSO | Pending |

Do not combine large corpus edits with runtime/LiveView changes in the same
change set.

---

## Deliberately later

Until Themes 2 and 3 are in place, defer:

- Splitting into a Phoenix umbrella or redesigning application chrome for its
  own sake
- Introducing Ash or an application-side user database
- Adding major new external frameworks (e.g. NIST AI RMF, SOC 2) before the
  current four are fully exercised through Results and evidence
- Treating Surreal SCHEMAFULL as a replacement for offline corpus lint

---

## Definition of done (near-term product bar)

The near-term bar is met when:

- A governance team can run a **combined** assessment: classify under the EU AI
  Act, complete domain questions, attach evidence, review applicability and
  residual coverage, and generate corpus-backed documents.
- Collaborators can participate under enforced roles.
- CI enforces format, corpus lint, and unit tests on every change.
- Runtime docs describe the same routes and storage model the code implements.

---

## Risks

| Risk | Response |
|---|---|
| Surreal Cloud routing or idle pause mistaken for product auth failure | Retain client retries and multi-pass runtime ensure; keep deploy fingerprint checks |
| New writes blocked by record permissions | Extend `ensure_runtime` probes (or tagged Surreal tests) for each new path |
| Results quality limited by mapping/activation data | Ship Results against fixtures and current edges; prioritize Theme 4 where the UI exposes gaps |
| Divergent artifact storage paths | Resolve under Theme 1 before stacking Library or evidence features |

---

## Planning workflow

This file is the sequencing source for contributors and automation.

Issue tracking (Linear or equivalent) should mirror **Themes 1–5** with issues
per delivery slice A–H, each linking back here. Create those issues next; then
implement starting at slice A unless a maintainer directs otherwise.
