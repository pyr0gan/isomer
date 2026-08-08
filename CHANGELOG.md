# Content releases

## 1.0.0 — 2026-08-08
First complete content layer. Corpus: 176 requirements, 13 domains,
13 rubrics, 75 mapping edges, 1 regulatory ruleset, 48 questions,
4 templates.

- annex-sl-core/1.0 — 27 shared management-system requirements (clauses 4-10)
- iso42001/2023 — 38 Annex A controls (9 objectives)
- iso27001/2022 — 93 Annex A controls (4 themes); vocab extended to 13 domains
- rubrics — 13 domains x 5 levels, all-criteria-cumulative scoring
- mappings — iso42001-2023--iso27001-2022 (38 edges);
  eu-ai-act-2024-2026-1744--iso42001-2023 (37 edges; mixed iso42001 +
  annex-sl-core targets)
- eu-ai-act/2024+2026-1744 — 18 obligations, consolidated post-Omnibus
  (Reg. 2026/1744) dates; classification ruleset with per-pathway
  applicable_from
- questions — 48 assessment questions (L1/L2 focus) keyed to requirements
- templates — AI policy, integrated SoA, impact assessment
  (42005-shaped + FRIA extension), AI system register
- tools — validate.py (schemas + semantic checks incl. YAML-date
  normalization, questions/templates), delta_report.py (integration
  coverage), check_content_charset.py (reject non-Latin letter leakage)

Review status: all mapping edges and legal-obligation paraphrases carry
reviewer: claude-draft pending human review. Legal review of eu-ai-act
paraphrases required before tenant-facing use.

Known scope exclusions: GPAI provider obligations (arts 53-55),
importer/distributor duties, Art. 6(3) high-risk exemption filter,
L3/L4-targeted questions.
