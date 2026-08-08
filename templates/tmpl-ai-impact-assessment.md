---
id: tmpl-ai-impact-assessment
name: AI System Impact Assessment (42005-shaped, FRIA-extended)
version: "1.0"
kind: template
covers:
  - iso42001/2023/A.5.2
  - iso42001/2023/A.5.3
  - iso42001/2023/A.5.4
  - iso42001/2023/A.5.5
  - eu-ai-act/2024+2026-1744/art-27
merge_fields: [system.name, system.owner, assessment.date, assessment.assessor, assessment.trigger]
---

# Impact Assessment — {{system.name}}

**Owner:** {{system.owner}} · **Assessor:** {{assessment.assessor}}
**Date:** {{assessment.date}} · **Trigger:** {{assessment.trigger}}

## 1. System context
Purpose, deployment context, affected populations, degree of autonomy,
data sensitivity. Reference the system register entry.

## 2. Intended benefits
What the system is for and for whom; the yardstick harms are weighed against.

## 3. Impacts on individuals and groups
Assess per category, with likelihood/severity and affected populations:
fairness and discrimination · safety · privacy · transparency and redress ·
economic effects · accessibility · effects on vulnerable groups.

## 4. Societal impacts
Environmental · labor and economic structure · culture, norms and
institutions · misinformation potential. Mark "not applicable" only with a
sentence of reasoning.

## 5. Fundamental rights extension (complete when in FRIA scope)
For deployments in scope of the fundamental rights impact assessment duty:
processes in which the system is used · categories of natural persons and
groups affected · specific risks of harm to fundamental rights · human
oversight measures · mitigation and internal governance arrangements ·
timing check: completed **before first use** · notification obligations.

## 6. Mitigations and residual assessment
Mitigation per material impact, the residual level, and who accepts it.

## 7. Decision and conditions
Proceed / proceed with conditions / do not proceed. Conditions become
tracked actions. Re-assessment triggers (substantial modification, new
population, incident).

## 8. Record control
Retention period, version, linkage to risk register entries.
