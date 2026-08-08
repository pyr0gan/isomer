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
tools/delta_report.py                                coverage delta (covered/partial/…)
tools/check_content_charset.py                       reject non-Latin letters in content
```

Current frameworks: `annex-sl-core/1.0` (shared clauses 4–10),
`iso42001/2023` (Annex A, 38 controls), `iso27001/2022` (Annex A, 93 controls),
`eu-ai-act/2024+2026-1744` (18 obligations; consolidated post-Omnibus).

Cross-framework mappings (queryable residual work by tier):

| Mapping set | Story |
|---|---|
| `mappings/iso42001-2023--iso27001-2022.yaml` | ISMS → AIMS residual |
| `mappings/eu-ai-act-2024-2026-1744--iso42001-2023.yaml` | AIMS → AI Act residual |

```
npm run report:delta -- mappings/iso42001-2023--iso27001-2022.yaml
npm run report:delta -- mappings/eu-ai-act-2024-2026-1744--iso42001-2023.yaml
```

The AI Act → AIMS set may target **both** `iso42001/2023` controls and
inherited `annex-sl-core/1.0` clauses in one file (`to_framework` names the
AIMS umbrella; per-edge targets carry their own namespace).

Classification ruleset: `rulesets/eu-ai-act-classification.yaml`.
Evaluate with first-match semantics (outcome order is semantic):

```
npm run ruleset:evaluate -- \
  --ruleset rulesets/eu-ai-act-classification.yaml \
  --answers '{"role":"provider","annex-iii-area":"employment"}'
```

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
  must not contain non-Latin letters (CJK etc.); `npm run lint:charset`
  enforces this (common typography like em dashes is allowed).
- **annex-sl-core** is a pseudo-framework holding the harmonized
  clauses 4-10 shared by ISO/IEC 27001:2022 and ISO/IEC 42001:2023.
  Both standards inherit it; standard-specific deltas live in each
  requirement's `specializations` and the manifest's `extension_points`
  (notably 42001's 6.1.4 and 8.4 impact assessment clauses).
