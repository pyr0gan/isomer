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
vocab/domains.yaml                                   maturity domains (9 AIMS + 4 ISMS)
schemas/*.schema.json                                JSON Schema 2020-12 definitions
tools/validate.py                                    CI validator
tools/delta_report.py                                ISMS→AIMS coverage delta
```

Current frameworks: `annex-sl-core/1.0` (shared clauses 4–10),
`iso42001/2023` (Annex A, 38 controls), `iso27001/2022` (Annex A, 93 controls).

Cross-framework mapping: `mappings/iso42001-2023--iso27001-2022.yaml`
(38 edges). Integration delta (what an ISMS org still builds for AIMS):

```
npm run report:delta -- mappings/iso42001-2023--iso27001-2022.yaml
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
