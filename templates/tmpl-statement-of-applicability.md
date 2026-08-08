---
id: tmpl-statement-of-applicability
name: Statement of Applicability (integrated ISMS+AIMS)
version: "1.0"
kind: template
covers:
  - annex-sl-core/1.0/6.1.3
merge_fields: [org.name, soa.approval_date, soa.approver, soa.content_release]
---

# {{org.name}} — Statement of Applicability

**Approved:** {{soa.approval_date}} by {{soa.approver}}
**Content release:** {{soa.content_release}} (control references pin to this release)

## Rules of this document
1. Every reference control (ISO/IEC 42001:2023 Annex A and ISO/IEC 27001:2022
   Annex A) appears exactly once: **included**, **excluded**, or **modified**.
2. Every decision carries a justification. An exclusion without written
   justification is treated as a defect, not a decision.
3. Included controls link to their implementing evidence.
4. Risk owners approve the treatment plan this SoA reflects, and residual
   risk acceptance is recorded separately.

## Control decisions

| Control | Title | Decision | Justification | Evidence link | Owner |
|---|---|---|---|---|---|
| iso42001/2023/A.2.2 | AI policy | included | … | … | … |
| … | … | … | … | … | … |

> Generate one row per control from the content release; the tool enforces
> completeness. Sort by framework, then reference.

## Exclusion register (extract)
Repeat every excluded control here with its full justification, so the
auditor's first question answers itself.
