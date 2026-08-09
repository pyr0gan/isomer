# isomer

<p align="center">
  <a href="https://surrealdb.com" title="SurrealDB">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/assets/logos/surrealdb-light.svg" />
      <img src="docs/assets/logos/surrealdb-dark.svg" alt="SurrealDB" width="240" style="max-width: 80%; height: auto;" />
    </picture>
  </a>
</p>

<p align="center">
  <a href="https://elixir-lang.org" title="Elixir">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/assets/logos/elixir-light.svg" />
      <img src="docs/assets/logos/elixir-dark.svg" alt="Elixir" width="180" style="max-width: 60%; height: auto;" />
    </picture>
  </a>
</p>

<p align="center"><strong>Built with <a href="https://surrealdb.com">SurrealDB</a> and <a href="https://elixir-lang.org">Elixir</a></strong></p>

**isomer** is a shared library of AI governance content — the requirements,
questions, and mappings that make up an integrated security + AI management
playbook.

The content lives in plain YAML and Markdown in this repo. Elixir tooling
checks it, and SurrealDB stores it so apps (and a future questionnaire UI) can
query it.

Version **1.1.0** — see [`CHANGELOG.md`](CHANGELOG.md).

---

## What you get

| Kind | What it is |
|---|---|
| **Requirements** | Controls and legal obligations (what you must do), with evidence expectations |
| **Mappings** | How one framework covers another (and where the gaps are) |
| **Questions** | Assessment questions for maturity domains |
| **Rulesets** | Guided classification (for example EU AI Act risk category) |
| **Rubrics** | Maturity levels L0–L4 per domain |
| **Templates** | Document starters (policy, SoA, impact assessment, …) |

### Frameworks in the corpus

| Framework | Contents |
|---|---|
| Shared management system (`annex-sl-core/1.0`) | Clauses 4–10 used by both ISO 27001 and ISO 42001 |
| ISO/IEC 42001:2023 | AI management — Annex A controls |
| ISO/IEC 27001:2022 | Information security — Annex A controls |
| EU AI Act (`2024+2026-1744`) | Legal obligations, dates after the 2026 Omnibus update |

Cross-framework mapping files:

- ISO 27001 → ISO 42001 residual work  
- EU AI Act → ISO 42001 / shared clauses residual work  

---

## Quick start

You need **Elixir 1.20.3+** and **OTP 29+** (versions are pinned in `mise.toml`).

<details>
<summary><strong>Install dependencies and check the corpus</strong></summary>

```bash
mix deps.get
mix lint
```

`mix lint` checks schemas, cross-references, and that content stays in Latin
script (no accidental CJK characters, and so on).

</details>

<details>
<summary><strong>Connect to SurrealDB (optional)</strong></summary>

1. Copy `.env.example` → `.env` and fill in Surreal + Vault values.  
   Never commit `.env`. The Surreal password comes from **Vault**, not from a
   plain `SURREAL_PASSWORD` variable.
2. Smoke-test the connection:

```bash
mix isomer.db.ping
```

If `.env` uses 1Password `op://` references:

```bash
op run --env-file=.env -- mix isomer.db.ping
```

3. Publish the corpus into SurrealDB:

```bash
mix isomer.db.sync
# or preview only:
mix isomer.db.sync --dry-run
```

4. (Optional) Create assessment/auth tables for the questionnaire design:

```bash
mix isomer.db.ensure_runtime
```

Design notes for the upcoming LiveView questionnaire:
[`docs/assessment-runtime.md`](docs/assessment-runtime.md).

</details>

---

## Common commands

<details>
<summary><strong>Validate content</strong></summary>

| Command | What it does |
|---|---|
| `mix lint` | Full content check (schemas + charset) |
| `mix isomer.validate` | Schema and cross-reference checks only |
| `mix isomer.charset` | Reject non-Latin letters in content files |

</details>

<details>
<summary><strong>Reports and classification</strong></summary>

Coverage buckets for a mapping file (covered / partial / adjacent / net-new):

```bash
mix isomer.delta mappings/iso42001-2023--iso27001-2022.yaml
mix isomer.delta mappings/eu-ai-act-2024-2026-1744--iso42001-2023.yaml
```

EU AI Act classification (first matching outcome wins; order in the YAML matters):

```bash
mix isomer.ruleset.eval \
  --ruleset rulesets/eu-ai-act-classification.yaml \
  --answers '{"role":"provider","annex-iii-area":"employment"}'
```

</details>

<details>
<summary><strong>SurrealDB</strong></summary>

| Command | What it does |
|---|---|
| `mix isomer.db.ping` | Check Vault + Surreal connectivity |
| `mix isomer.db.sync` | Load corpus into Surreal; remove stale repo-managed rows |
| `mix isomer.db.sync --dry-run` | Show counts without writing |
| `mix isomer.db.ingest_sample` | Write one sample requirement (sanity check) |
| `mix isomer.db.ensure_runtime` | Auth + org/assessment tables for the questionnaire |

</details>

<details>
<summary><strong>Software bill of materials</strong></summary>

CycloneDX JSON (dev dependency; do not run with `MIX_ENV=prod`):

```bash
mix isomer.sbom --pretty
# writes bom.cdx.json
```

CI also generates this file and uploads it as an artifact.

</details>

---

## How the content is organized

<details>
<summary><strong>Repository layout</strong></summary>

```
frameworks/<name>/<version>/framework.yaml       framework manifest
frameworks/<name>/<version>/requirements/*.yaml  one file per requirement
mappings/*.yaml                                  links between frameworks
rulesets/*.yaml                                  classification questionnaires
rubrics/<domain>.yaml                            maturity levels L0–L4
questions/<domain>.yaml                          assessment questions
templates/tmpl-*.md                              document templates
vocab/domains.yaml                               domain list
schemas/*.schema.json                            JSON Schema definitions
lib/                                             Elixir tooling
docs/                                            design notes + logo assets
```

</details>

**Questions** (48 today) lean toward practical L1/L2 self-report and can point
at several requirements at once. **Templates** list which requirements they
help evidence (`covers` in the frontmatter).

---

## Rules for writing content

Keep these in mind when editing YAML:

- **No copied standard text.** Summaries are original paraphrases. Readers
  still need their own licensed ISO copies. Legal paraphrases are tooling aids,
  not legal advice.
- **IDs match folders.** A requirement id looks like
  `framework/version/ref` (for example `iso42001/2023/A.5.2`) and must sit in
  the matching directory.
- **Every requirement lists evidence expectations** — what artifact would prove
  it.
- **Legal obligations need an effective date** (`applicable_from`). Dates are
  data, not hard-coded in the app.
- **Classification outcomes can override dates.** If a ruleset outcome sets
  `applicable_from`, that date wins for the obligations it activates.
- **Rulesets stop at the first match.** Put stronger screens (for example
  prohibited uses) before weaker ones.
- **Partial or conflicting mappings need a short gap note.**
- **Prefer Latin script** in content files (`mix isomer.charset`); normal
  punctuation such as em dashes is fine.
- **Shared clauses** live in `annex-sl-core`. ISO 27001 and ISO 42001 both
  inherit them; standard-specific extras stay on each requirement.

---

## Learn more

- Changelog: [`CHANGELOG.md`](CHANGELOG.md)
- Questionnaire + Surreal auth design: [`docs/assessment-runtime.md`](docs/assessment-runtime.md)
- Agent/contributor notes: [`AGENTS.md`](AGENTS.md)
