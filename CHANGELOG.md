# Content releases

## Unreleased

- Tooling — replace Python (`tools/`) and Node (`src/`, `scripts/`, npm)
  with Elixir Mix tasks (`mix lint`, `mix isomer.db.*`, etc.). Surreal
  connectivity uses the official Elixir SDK over WSS; password still from Vault.
- SBoM — CycloneDX via EEF `sbom` (`mix isomer.sbom` → `bom.cdx.json`);
  CI uploads the artifact. Elixir/OTP bumped to **1.19.4 / 27.3.4** for the
  generator toolchain.

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
- tools — originally Python/JS validators and Surreal sync; replaced by
  Elixir Mix tasks (`mix lint`, `mix isomer.db.sync`, etc.) after 1.0.0

Review status: all mapping edges and legal-obligation paraphrases carry
reviewer: claude-draft pending human review. Legal review of eu-ai-act
paraphrases required before tenant-facing use.

Known scope exclusions: GPAI provider obligations (arts 53-55),
importer/distributor duties, Art. 6(3) high-risk exemption filter,
L3/L4-targeted questions.
