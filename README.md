# isomer

Versioned, framework-agnostic corpus powering an integrated ISMS+AIMS
playbook. Requirements, mappings, rubrics, and rulesets are data; 
eventual product will render and provide a workflow engine for this repo.

## Layout

```
frameworks/<framework>/<version>/framework.yaml      manifest
frameworks/<framework>/<version>/requirements/*.yaml one file per requirement
mappings/<from>--<to>.yaml                           typed cross-framework mappings
rulesets/*.yaml                                      regulatory classification rulesets
rubrics/<domain>.yaml                                per-domain maturity rubrics (L0–L4)
vocab/domains.yaml                                   the nine maturity domains
schemas/*.schema.json                                JSON Schema 2020-12 definitions
tools/validate.py                                    CI validator
```

## Conventions

- **No verbatim standard text.** `text_summary` is always an original
  paraphrase. Customers hold their own licensed copies of ISO standards.
- **IDs** are `<framework>/<version>/<ref>` and must match the file's
  directory. Refs use the source document's own numbering (`6.1.3`,
  `A.6.2.4`, `art-26`).
- **`evidence_expectations` is mandatory** on every requirement — it is
  what the product tracks artifacts against.
- **Obligations** (`type: obligation`, `authority: legal`) must carry
  `applicable_from`; effective dates are data, never code. (Regulation
  (EU) 2026/1744 moving the AI Act high-risk dates is the canonical
  example of why.)
- **Mappings** are directed and typed; `partially_satisfied_by` and
  `conflicts` require a gap note. Mappings reference framework
  *versions*, and go `status: stale` when either side revs.
- **annex-sl-core** is a pseudo-framework holding the harmonized
  clauses 4-10 shared by ISO/IEC 27001:2022 and ISO/IEC 42001:2023.
  Both standards inherit it; standard-specific deltas live in each
  requirement's `specializations` and the manifest's `extension_points`
  (notably 42001's 6.1.4 and 8.4 impact assessment clauses).

## Lint / validation

Keep source files clean before sync:

```
pip install pyyaml jsonschema
npm install
npm run lint              # corpus validator + ESLint
npm run lint:corpus       # YAML / JSON Schema checks (tools/validate.py)
npm run lint:js           # JavaScript (src/, scripts/)
```

`lint:corpus` checks schema conformance, ID uniqueness, ID/path coherence,
domain vocabulary resolution, mapping endpoint resolution, mandatory gap
notes, effective dates on legal obligations, and maturity-rubric coverage
(one `rubrics/<domain>.yaml` per vocab domain, levels L0–L4 in order).

CI runs `npm run lint` on every PR and push to `main`. Live Surreal sync
runs separately on `main` (see `.github/workflows/sync-corpus.yml`).
