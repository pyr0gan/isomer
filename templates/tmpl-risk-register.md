---
id: tmpl-risk-register
name: Risk Register (AI + information security)
version: "1.0"
kind: template
covers:
  - annex-sl-core/1.0/6.1.1
  - annex-sl-core/1.0/6.1.2
  - iso42001/2023/A.5.2
merge_fields: [org.name, register.last_updated, register.approver, register.methodology_ref]
---

# {{org.name}} — Risk Register

**Last updated:** {{register.last_updated}}
**Approved by:** {{register.approver}}
**Methodology:** {{register.methodology_ref}}

Living register of AI and information security risks. Every entry has a
named owner. Impact assessments and system-register ids key into this
register; the Statement of Applicability reflects the treatment decisions
recorded here.

## Entry schema

| Field | Content |
|---|---|
| risk_id | Stable identifier (link from system register / impact assessment) |
| title | Short description of the risk |
| category | AI / information security / both |
| system_id | Related AI system id (if any); blank for enterprise-wide risks |
| description | Threat, vulnerability, and affected assets or stakeholders |
| owner | Named accountable person |
| likelihood | Per methodology scale |
| severity | Per methodology scale (impact on individuals, groups, or org) |
| inherent_level | Combined score before treatment |
| treatment | mitigate / transfer / avoid / accept — with plan summary |
| controls | Implementing controls / evidence links (policies, SoA rows, tickets) |
| residual_level | Score after treatment |
| acceptance | Residual acceptance decision and date (if accept) |
| review_date | Next scheduled review |

## Register rows

| risk_id | title | category | system_id | owner | likelihood | severity | treatment | residual | review_date |
|---|---|---|---|---|---|---|---|---|---|
| R-… | … | … | … | … | … | … | … | … | … |

## Discipline
- No silent risks: if an impact assessment or incident identifies a risk,
  it appears here within the review cycle.
- Owners confirm treatment progress at each `review_date`.
- Acceptance of residual risk is recorded (who, when, why) — not implied
  by leaving a row unchanged.
- Methodology (`{{register.methodology_ref}}`) defines scales and
  acceptance criteria; this register applies them, it does not redefine them.
