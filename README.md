# isomer
 
**AI and information security governance content as code.** ISO/IEC 42001, ISO/IEC 27001 and the EU AI Act, expressed as schema-checked YAML and Markdown that you can diff, lint, and query.
 
[Run it locally](#run-it-locally) · [Roadmap](docs/roadmap.md) · [Contributing](AGENTS.md)
 
![Organization dashboard with assessments and maturity metrics](docs/assets/screenshots/org-dashboard.png)
 
## Why this exists
 
Governance material usually ships as a PDF or a spreadsheet. It can't be diffed, it can't be tested, and it drifts out of date the moment a standard or a regulation moves.
 
isomer keeps the content in a repository instead. Requirements, cross-framework mappings, assessment questions and maturity rubrics are structured files with JSON Schemas behind them. A regulatory change becomes a pull request. The residual work between ISO 27001 and ISO 42001 becomes something you compute with `mix isomer.delta` rather than something you estimate.
 
Elixir tooling validates the corpus. SurrealDB stores it so applications can query it, including the assessment questionnaire in this repo.
 
## What's in the corpus
 
| Framework | Contents |
|---|---|
| Shared management system (`annex-sl-core/1.0`) | Clauses 4–10 used by both ISO 27001 and ISO 42001 |
| ISO/IEC 42001:2023 | AI management, Annex A controls |
| ISO/IEC 27001:2022 | Information security, Annex A controls |
| EU AI Act (`2024+2026-1744`) | Legal obligations, dates after the 2026 Omnibus update |
 
Two mapping files show what one framework leaves undone for another: ISO 27001 → ISO 42001, and EU AI Act → ISO 42001 / shared clauses.
 
Alongside the requirements themselves, the corpus carries **mappings** (framework-to-framework coverage and gaps), **questions** (48 assessment questions, weighted toward practical L1/L2 self-report), **rulesets** (guided classification, such as EU AI Act risk category), **rubrics** (L0–L4 maturity per domain), and **templates** (policy, Statement of Applicability, impact assessment, each declaring which requirements it evidences).
 
## Run it locally
 
There is no hosted demo. You run the whole stack on your own machine: the Phoenix app, a SurrealDB server, and a Vault dev server. The app reads the SurrealDB root password from Vault, so you need both.
 
You need:
 
- **Elixir 1.20.3+** and **OTP 29+**. Both are pinned in `mise.toml`, so `mise install` sets them up.
- **SurrealDB** 3.x, the `surreal` CLI ([install](https://surrealdb.com/docs/surrealdb/installation)).
- **Vault**, the `vault` CLI ([install](https://developer.hashicorp.com/vault/install)). Dev mode is enough.
 
**1. Start SurrealDB and Vault.** Use two terminals and leave both running.
 
```bash
# Terminal 1: SurrealDB, data kept in ./.surreal-data
surreal start --user root --pass root --bind 127.0.0.1:8000 rocksdb:.surreal-data
 
# Terminal 2: Vault in dev mode (in memory, fixed root token)
vault server -dev -dev-root-token-id=dev-root
```
 
**2. Store the SurrealDB password in Vault.** Vault dev mode forgets everything when it stops, so run this again each time you restart Vault.
 
```bash
VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=dev-root vault kv put secret/surreal password=root
```
 
**3. Point the app at both.** Create `.env` in the repo root. It is gitignored.
 
```bash
cat > .env <<'EOF'
SURREAL_URL=ws://127.0.0.1:8000/rpc
SURREAL_NAMESPACE=main
SURREAL_DATABASE=main
SURREAL_USERNAME=root
VAULT_ADDR=http://127.0.0.1:8200
VAULT_TOKEN=dev-root
VAULT_SECRET_PATH=secret/data/surreal
VAULT_SECRET_FIELD=password
EOF
```
 
**4. Install, load the corpus, and start the app.**
 
```bash
mix setup                      # deps, assets, and git pre-commit hooks
mix isomer.db.ping             # should print "ok": true
mix isomer.db.sync             # load frameworks, mappings, questions, templates
mix isomer.db.ensure_runtime   # create auth, org, and assessment tables
mix phx.server
```
 
Open <http://localhost:4000>, create an account on the login page, and you land on **Organizations**. Create an org to start an assessment.
 
Evidence files you attach are kept in memory and lost on restart. To keep them on disk, start the server with `EVIDENCE_BACKEND=local EVIDENCE_LOCAL_ROOT=.evidence mix phx.server`. These two must be set in the shell; `.env` is read too late for them.
 
To start over, stop SurrealDB and delete `.surreal-data/`. If you only want to lint the corpus, you don't need SurrealDB or Vault at all: `mix setup && mix lint`.
 
`mix setup` wires up `.githooks/` so commits run `mix format`, compile with warnings-as-errors, and `mix lint` before they land, matching CI. Re-run `mix git.hooks` if the hooks go missing, or run the gate manually with `mix precommit`.
 
<details>
<summary>
 <strong>Using a remote SurrealDB or Vault</strong>
</summary>
 
`.env.example` lists every variable for a hosted setup, such as Surreal Cloud with `wss://…/rpc` and a real Vault with a token or AppRole. The Surreal password always comes from **Vault**, never from a plain `SURREAL_PASSWORD`. If `.env` uses 1Password `op://` references, wrap commands: `op run --env-file=.env -- mix isomer.db.ping`.
 
See [`docs/assessment-runtime.md`](docs/assessment-runtime.md) and [`docs/deploy.md`](docs/deploy.md).
 
</details>
 
<details>
<summary>
 <strong>All mix tasks</strong>
</summary>
 
| Command | What it does |
|---|---|
| `mix lint` | Full content check (schemas plus charset) |
| `mix isomer.validate` | Schema and cross-reference checks only |
| `mix isomer.charset` | Reject non-Latin letters in content files |
| `mix isomer.delta <mapping>` | Coverage buckets for a mapping: covered, partial, adjacent, net-new |
| `mix isomer.ruleset.eval` | Run a classification ruleset against a set of answers |
| `mix isomer.sbom --pretty` | Write a CycloneDX SBoM to `bom.cdx.json` (dev only, never `MIX_ENV=prod`) |
| `mix isomer.db.ping` | Check Vault and Surreal connectivity |
| `mix isomer.db.sync` | Load the corpus into Surreal, removing stale repo-managed rows |
| `mix isomer.db.sync_sbom` | Upsert the SBoM when dependencies changed |
| `mix isomer.db.ingest_sample` | Write one sample requirement as a sanity check |
| `mix isomer.db.ensure_runtime` | Create auth and org/assessment tables for the questionnaire |
 
EU AI Act classification, where the first matching outcome wins and YAML order matters:
 
```bash
mix isomer.ruleset.eval \
  --ruleset rulesets/eu-ai-act-classification.yaml \
  --answers '{"role":"provider","annex-iii-area":"employment"}'
```
 
On `main`, `sync-corpus.yml` runs `mix isomer.db.sync_sbom` after the corpus sync. The current bill of materials lives at Surreal record `sbom:isomer_tooling`, not as a GitHub Actions artifact.
 
</details>

<details>
<summary>
 <strong>Repository layout</strong>
</summary>
 
```text
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
docs/                                            design notes, screenshots, logo assets
```

</details>

## Contributing content
 
The rules that the linter can't catch:
 
- **No copied standard text.** Summaries are original paraphrases.
- **IDs match folders.** A requirement id looks like `framework/edition/ref`, for example `iso42001/2023/A.5.2`, and must sit in the matching directory. Framework `version` is the standard edition, not the Mix app version.
- **Every requirement lists evidence expectations**, meaning the artifact that would prove it.
- **Legal obligations need an `applicable_from` date.** Dates are data, never hard-coded. A ruleset outcome that sets `applicable_from` overrides the default for the obligations it activates.
- **Rulesets stop at the first match**, so put stronger screens such as prohibited uses ahead of weaker ones.
- **Partial or conflicting mappings need a short gap note.**
- **Shared clauses live in `annex-sl-core`.** ISO 27001 and ISO 42001 both inherit them; standard-specific extras stay on each requirement.
Full contributor notes are in [`AGENTS.md`](AGENTS.md).
 
## Scope and limits
 
isomer paraphrases; it does not reproduce. You still need your own licensed copies of the ISO standards. The legal paraphrases are tooling aids and not legal advice.
 
## Learn more
 
- Versioning, tooling vs content: [`docs/versioning.md`](docs/versioning.md)
- Assessment runtime and Surreal auth design: [`docs/assessment-runtime.md`](docs/assessment-runtime.md)
- Self-hosting with Docker: [`docs/deploy.md`](docs/deploy.md)

## License
 
This project is not currently under a license. Should you or your agents choose to misbehave and claim this work as your own, remember that Karma rides a slow pony.
 
---

## Built with

This project is built with and utilizes the following technologies:
 
<p align="center">
  <a href="https://elixir-lang.org" title="Built with Elixir" style="text-decoration: none;">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/assets/logos/elixir-light.svg" />
      <img src="docs/assets/logos/elixir-dark.svg" alt="Built with Elixir" width="105" height="36" style="display: inline-block; border: 0;" />
    </picture>
  </a>
</p>
<p align="center">
  <a href="https://surrealdb.com" title="Built with SurrealDB" style="text-decoration: none;">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/assets/logos/surrealdb-light.svg" />
      <img src="docs/assets/logos/surrealdb-dark.svg" alt="Built with SurrealDB" width="150" height="36" style="display: inline-block; border: 0;" />
    </picture>
  </a>
</p>
