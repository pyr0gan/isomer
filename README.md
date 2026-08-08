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

## Validation

```
pip install pyyaml jsonschema
python3 tools/validate.py
```

Checks schema conformance, ID uniqueness, ID/path coherence, domain
vocabulary resolution, mapping endpoint resolution, mandatory gap notes,
and effective dates on legal obligations.

## SurrealDB sync

The YAML corpus is the source of truth. Sync it into SurrealDB (password
via HashiCorp Vault — see `.env.example`):

```
npm install
npm run db:sync:dry-run   # load + report only
npm run db:sync           # upsert domains/frameworks/requirements (+ mappings/rulesets when present)
```

CI validates on every PR and runs a live sync on pushes to `main`
(`.github/workflows/`). Configure the Vault/Surreal secrets listed in
`AGENTS.md` on the GitHub repository.
