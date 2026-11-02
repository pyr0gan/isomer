# Deploying IsomerWeb

The assessment UI is a Phoenix endpoint inside the same Mix app as the corpus
tooling. SurrealDB stays the system of record; this process only holds **user**
JWTs at runtime. Root/Vault credentials are for Mix tasks (`sync`,
`ensure_runtime`), not for the web process’s request path.

## Prerequisites

1. Surreal namespace/database already has corpus content (`mix isomer.db.sync`)
   and runtime DDL (`mix isomer.db.ensure_runtime`).
2. Generate a Phoenix secret: `mix phx.gen.secret`.

Web runtime env (minimum):

| Variable | Purpose |
|---|---|
| `SECRET_KEY_BASE` | Cookie / LiveView signing (`_isomer_key` is `Secure` + `HttpOnly` + `SameSite=Lax` in prod) |
| `PHX_HOST` | Public hostname (no scheme) |
| `PORT` | HTTP listen port (platform usually sets this) |
| `PHX_SERVER` | `true` so the endpoint accepts connections |
| `SURREAL_URL` | `wss://…/rpc` |
| `SURREAL_NAMESPACE` / `SURREAL_DATABASE` | Same as sync |
| `VAULT_*` | Only needed if you run Mix tasks in the same image |
| `EVIDENCE_BACKEND` | Optional: `memory` / `local` / `s3` (auto: S3 if `EVIDENCE_S3_*` set, else local if `EVIDENCE_LOCAL_ROOT`, else memory) |
| `EVIDENCE_LOCAL_ROOT` | Filesystem root when using local evidence storage |
| `EVIDENCE_S3_BUCKET` / `EVIDENCE_S3_ACCESS_KEY_ID` / `EVIDENCE_S3_SECRET_ACCESS_KEY` | Required for S3-compatible evidence storage |
| `EVIDENCE_S3_REGION` / `EVIDENCE_S3_ENDPOINT` / `EVIDENCE_S3_FORCE_PATH_STYLE` | Optional S3 region, custom endpoint (R2/MinIO), path-style |

Signup/signin use Surreal record access and do **not** need the Vault password
on the web process. Keep Vault on a one-off release command or CI for schema
sync.

### Web vs Actions Surreal target

The web app and `sync-corpus.yml` must talk to the **same** Surreal instance.
`mix isomer.db.ensure_runtime` and the Actions "Print Surreal target fingerprint"
step log `host=… ns=… db=…`; compare that with the `SURREAL_URL` your web
process uses (host only; do not paste secrets into tickets).

If the hosts differ, Settings saves fail with "no such field" for `comfort_level`
even when CI `ensure_runtime` is green — the schema was applied to the other DB.
Fix the web process's `SURREAL_*` env to match Actions, then re-run **Sync
corpus to SurrealDB** (`workflow_dispatch`).

The app also writes prefs into FLEXIBLE `user.guide_prefs` and keeps a session
overlay when flat columns lag on a Surreal Cloud compute node, so Settings
remains usable while `ensure_runtime` converges.

`ensure_runtime` applies schema across several fresh connections (default 8,
`ENSURE_RUNTIME_PASSES`) because Surreal Cloud hostnames often resolve to
multiple IPs — a single DEFINE + probe can be green in Actions while the web
process still misses `artifact` / pref fields. Each pass runs root INFO checks, a
root write probe, and a **record-auth** signup/update/`SELECT artifact` probe.


### Surreal connect timeouts on sign-in

If web logs show `auth signin failed … reason=could not connect:
%Mint.TransportError{reason: :timeout}` (or `RPC use timed out during setup`),
the password was never checked — the web process failed to open / set up the Surreal
WSS session. Common causes:

1. **Surreal Cloud idle pause** (free / low tiers) — wake the instance in the
   Surreal console, wait ~30s, retry sign-in.
2. **Wrong or stale `SURREAL_URL`** in the web process's environment.
3. **Regional lag** — hosting the app far from the Surreal Cloud region adds
   latency. Latency alone rarely hits 10–15s, but combined with a cold
   instance it can.

The web client retries transient connect failures a few times and keeps an
existing session cookie when LiveView mount times out (so a pause does not
force a logout loop).

## Docker

There is no hosted demo; for day-to-day use, run locally (README, "Run it
locally"). To self-host, build the release image from the `Dockerfile`:

```bash
docker build -t isomer .
docker run --rm -p 4000:4000 \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e PHX_HOST=your.host.example \
  -e SURREAL_URL=wss://…/rpc -e SURREAL_NAMESPACE=main -e SURREAL_DATABASE=main \
  isomer
```

The image sets `PHX_SERVER=true` and listens on `PORT` (default `4000`). Health
checks should hit `/health` (plain-text liveness; not `/login`). Prod responses
send `Strict-Transport-Security: max-age=31536000` and the session cookie is
`Secure`, so put the app behind a TLS-terminating proxy; the app does not
HTTP→HTTPS redirect itself, so `/health` stays 200 over plain HTTP.

Public discovery files (static under `priv/static/`):

| Path | Purpose |
|---|---|
| `/health` | Liveness probe |
| `/robots.txt` | Crawler policy |
| `/llms.txt` | LLM/context summary ([llmstxt.org](https://llmstxt.org/)) |
| `/humans.txt` | Human-readable contact |
| `/.well-known/security.txt` (also `/security.txt`) | Vulnerability disclosure ([RFC 9116](https://www.rfc-editor.org/rfc/rfc9116.html)) |

Before the first deploy (and after corpus changes), apply Surreal content +
runtime DDL from a machine that has Vault access — the release image does not
run Mix sync tasks:

```bash
mix isomer.db.sync
mix isomer.db.ensure_runtime
```

Re-run `ensure_runtime` after sync so record users can `SELECT` corpus tables
(including `question_set`). The Docker image ships `vocab/domains.yaml` for
domain labels in the assessment UI; question text itself is loaded from Surreal.

If signup says the email already exists but sign-in fails, the password does not
match the stored argon2 hash (Surreal returns “No record was returned”). Reset
with root credentials:

```bash
mix isomer.db.reset_password --email you@example.com --password 'new-secret'
```

## Railway

1. New project → deploy from this repo.
2. Set the start command to the release boot (Dockerfile `CMD` already does
   this) or, for a simpler Nixpacks Mix run:

   ```
   mix deps.get && mix compile && PHX_SERVER=true mix phx.server
   ```

   Prefer the Dockerfile / release path for production.
3. Variables: same table as above; Railway injects `PORT`.
4. Set `PHX_HOST` to your `*.up.railway.app` hostname (or custom domain).

## Local

See the README, "Run it locally": local SurrealDB + Vault dev server, then
`mix setup`, `mix isomer.db.sync`, `mix isomer.db.ensure_runtime`,
`mix phx.server` → http://localhost:4000.

UI assets live under `assets/` and compile to `priv/static/assets/` via Tailwind v4 and esbuild (Petal Components). Production images run `mix assets.deploy` in the Dockerfile.
