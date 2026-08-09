# isomer

Versioned, framework-agnostic corpus powering an integrated ISMS+AIMS
playbook. Requirements, mappings, rubrics, rulesets, questions, and
templates are data; eventual product will render and provide a workflow
engine for this repo. Content release **1.0.0** — see `CHANGELOG.md`.

Tooling is **Elixir / Mix** (SurrealDB over WSS; password from Hashicorp Vault).

## Layout

```
frameworks/<framework>/<version>/framework.yaml      manifest
frameworks/<framework>/<version>/requirements/*.yaml one file per requirement
mappings/<from>--<to>.yaml                           typed cross-framework mappings
rulesets/*.yaml                                      regulatory classification rulesets
rubrics/<domain>.yaml                                per-domain maturity rubrics (L0–L4)
questions/<domain>.yaml                              assessment questions (L1/L2 focus)
templates/tmpl-*.md                                  document templates + covers frontmatter
vocab/domains.yaml                                   maturity domains (9 AIMS + 4 ISMS)
schemas/*.schema.json                                JSON Schema 2020-12 definitions
lib/                                                 Mix corpus + Surreal tooling
CHANGELOG.md                                         content release notes
```

Current frameworks: `annex-sl-core/1.0` (shared clauses 4–10),
`iso42001/2023` (Annex A, 38 controls), `iso27001/2022` (Annex A, 93 controls),
`eu-ai-act/2024+2026-1744` (18 obligations; consolidated post-Omnibus).

## Setup

Requires Elixir **1.17+** / OTP **25+** (see `mise.toml`). From the repo root:

```
mix deps.get
mix lint
```

Copy `.env.example` to `.env` for Surreal + Vault credentials (never commit `.env`).
If `.env` uses 1Password `op://` references:

```
op run --env-file=.env -- mix isomer.db.ping
```

## Commands

| Task | Purpose |
|---|---|
| `mix lint` / `mix lint.corpus` | Validate schemas + charset |
| `mix isomer.validate` | Schema + semantic corpus checks |
| `mix isomer.charset` | Reject non-Latin letters in content |
| `mix isomer.delta PATH` | Integration coverage buckets |
| `mix isomer.ruleset.eval --ruleset PATH --answers JSON` | First-match classification |
| `mix isomer.db.ping` | Surreal WSS + Vault smoke test |
| `mix isomer.db.sync` | Upsert corpus; prune stale `content_source="repo"` rows |
| `mix isomer.db.sync --dry-run` | Load + report counts only |
| `mix isomer.db.ingest_sample` | Upsert one requirement (hello-world write) |

Cross-framework mappings (queryable residual work by tier):

| Mapping set | Story |
|---|---|
| `mappings/iso42001-2023--iso27001-2022.yaml` | ISMS → AIMS residual |
| `mappings/eu-ai-act-2024-2026-1744--iso42001-2023.yaml` | AIMS → AI Act residual |

```
mix isomer.delta mappings/iso42001-2023--iso27001-2022.yaml
mix isomer.delta mappings/eu-ai-act-2024-2026-1744--iso42001-2023.yaml
```

The AI Act → AIMS set may target **both** `iso42001/2023` controls and
inherited `annex-sl-core/1.0` clauses in one file (`to_framework` names the
AIMS umbrella; per-edge targets carry their own namespace).

Classification ruleset: `rulesets/eu-ai-act-classification.yaml`.
Evaluate with first-match semantics (outcome order is semantic):

```
mix isomer.ruleset.eval \
  --ruleset rulesets/eu-ai-act-classification.yaml \
  --answers '{"role":"provider","annex-iii-area":"employment"}'
```

Assessment questions (`questions/<domain>.yaml`, 48 total) are L1/L2-weighted
and may list multiple `requirements` (cross-framework probes). Templates under
`templates/` carry `covers` frontmatter so completion can propose evidence
links; unused `merge_fields` warn in CI.

## Conventions

- **No verbatim standard text.** `text_summary` is always an original
  paraphrase. Customers hold their own licensed copies of ISO standards
  (and should treat legal-obligation paraphrases as tooling aids pending
  Official Journal review, not legal advice).
- **IDs** are `<framework>/<version>/<ref>` and must match the file's
  directory. Refs use the source document's own numbering (`6.1.3`,
  `A.6.2.4`, `art-26`). Framework versions may encode amendments
  (`2024+2026-1744`); a later amendment is a new version directory, not
  an in-place edit.
- **`evidence_expectations` is mandatory** on every requirement — it is
  what the product tracks artifacts against.
- **Obligations** (`type: obligation`, `authority: legal`) must carry
  `applicable_from`; effective dates are data, never code. (Regulation
  (EU) 2026/1744 moving the AI Act high-risk dates is the canonical
  example of why.)
- **Effective-date precedence (rulesets):** when a classification ruleset
  outcome carries `applicable_from`, that date **overrides** the
  requirement-level `applicable_from` for activated obligations. The
  requirement date records the earliest binding pathway (e.g. Annex III
  high-risk articles at `2027-12-02`); pathway-specific later dates
  (e.g. Annex I at `2028-08-02`) live on the matching outcome. Same
  article, two dates, resolved by classification.
- **Ruleset evaluation is first-match.** `outcomes[]` order is semantic,
  not cosmetic: prohibited screens first, then high-risk before
  transparency, transparency before the minimal-risk default. Implementers
  must walk outcomes in file order and stop at the first match.
- **Mappings** are directed and typed; `partially_satisfied_by` and
  `conflicts` require a gap note. Mappings reference framework
  *versions*, and go `status: stale` when either side revs. Content YAML
  must not contain non-Latin letters (CJK etc.); `mix isomer.charset`
  enforces this (common typography like em dashes is allowed).
- **Questions** key to rubric levels and requirement ids (`requirements` is
  an array — one answer can claim coverage across frameworks). Prefer
  L1/L2 self-report; L3/L4 distinction comes from rubric criteria against
  evidence. Every question should carry an `evidence_prompt`.
- **Templates** are markdown with YAML frontmatter (`covers`,
  `merge_fields`). Completing a template is an evidence event for the
  `covers` requirements (e.g. SoA → `annex-sl-core/1.0/6.1.3`).
- **annex-sl-core** is a pseudo-framework holding the harmonized
  clauses 4-10 shared by ISO/IEC 27001:2022 and ISO/IEC 42001:2023.
  Both standards inherit it; standard-specific deltas live in each
  requirement's `specializations` and the manifest's `extension_points`
  (notably 42001's 6.1.4 and 8.4 impact assessment clauses).
