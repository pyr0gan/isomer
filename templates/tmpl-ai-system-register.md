---
id: tmpl-ai-system-register
name: AI System Register
version: "1.0"
kind: template
covers:
  - iso42001/2023/A.4.2
  - iso42001/2023/A.4.3
merge_fields: [org.name, register.last_updated]
---

# {{org.name}} — AI System Register

**Last updated:** {{register.last_updated}}

One entry per AI system (built, bought, or embedded in procured products).
This register is the spine: impact assessments, risk entries, SoA evidence
and classification outcomes all key off the system id.

## Entry schema

| Field | Content |
|---|---|
| system_id | Stable identifier |
| name / purpose | What it is and what it's for |
| owner | Named accountable person |
| role | provider / deployer / developer / user (per system) |
| lifecycle_stage | intake / development / production / retired |
| classification | Output of the regulatory ruleset, with date |
| data | Data resources used: origin, categories, sensitivity flags |
| dependencies | Models, APIs, suppliers, compute — link supplier inventory |
| oversight | Human oversight arrangement, named persons |
| assessments | Links: impact assessment(s), risk entries |
| logs_monitoring | Where logs live, retention, monitoring dashboards |
| review_date | Next scheduled review |

## Register discipline
- No system operates outside the register; discovery of an unregistered
  system is a nonconformity with a CAPA entry.
- Classification re-runs on substantial modification or new use context.
