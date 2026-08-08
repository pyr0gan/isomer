---
id: tmpl-ai-policy
name: AI Policy
version: "1.0"
kind: template
covers:
  - iso42001/2023/A.2.2
  - iso42001/2023/A.2.3
  - annex-sl-core/1.0/5.2
merge_fields: [org.name, org.exec_sponsor, org.governance_lead, policy.effective_date, policy.review_cadence]
---

# {{org.name}} — AI Policy

**Owner:** {{org.exec_sponsor}} · **Governance lead:** {{org.governance_lead}}
**Effective:** {{policy.effective_date}} · **Review cadence:** {{policy.review_cadence}}

## 1. Purpose and scope
Why this policy exists, which entities, systems and lifecycle activities it
covers, and its relationship to the management system scope statement.

## 2. Principles
The principles {{org.name}} commits to for developing and using AI
(e.g. accountability, fairness, transparency, safety, privacy, human
oversight). State each as a commitment with a one-line operational meaning.

## 3. Roles and accountability
Accountable executive, governance lead, system owners, oversight roles.
Reference the AI role matrix rather than duplicating it.

## 4. Rules for AI use
Approval of new uses, acceptable use, prohibited applications (include
legally prohibited practices for your jurisdictions), and exception handling.

## 5. Lifecycle requirements
The gates AI systems pass through: impact assessment before deployment,
verification against acceptance criteria, monitoring in operation,
decommissioning. Reference the lifecycle procedure.

## 6. Data
Commitments on data rights, quality, provenance and privacy for AI
development and operation. Reference data governance procedures.

## 7. Transparency
What users and affected parties are told, and through which artifacts.

## 8. Suppliers and third parties
Expectations of AI suppliers and duties toward customers.

## 9. Alignment with other policies
Cross-references: information security policy, privacy policy, ethics/HR
policies. Note precedence rules where they interact.

## 10. Review
Review triggers (interval, regulation change, incidents, new use classes)
and the approval path for changes.
