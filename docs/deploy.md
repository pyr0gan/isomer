# Deploying IsomerWeb

The assessment UI is a Phoenix endpoint inside the same Mix app as the corpus
tooling. SurrealDB stays the system of record; this process only holds **user**
JWTs at runtime. Root/Vault credentials are for Mix tasks (`sync`,
`ensure_runtime`), not for the web dyno’s request path.

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

Signup/signin use Surreal record access and do **not** need the Vault password
on the web process. Keep Vault on a one-off release command or CI for schema
sync.

### Fly vs Actions Surreal target

The demo dyno (`isomer-demo`) and `sync-corpus.yml` must talk to the **same**
Surreal Cloud instance. After a sync run, compare:

```text
# from the Actions “Print Surreal target fingerprint” / ensure_runtime log
host=….aws-usw2.surreal.cloud ns=main db=main

# from the Fly machine
fly ssh console -a isomer-demo -C 'printenv SURREAL_URL'  # host only; do not paste secrets into tickets
```

If the hosts differ, Settings saves fail with “no such field” for `comfort_level`
even when CI `ensure_runtime` is green — the schema was applied to the other DB.
Fix: `fly secrets set SURREAL_URL=… SURREAL_NAMESPACE=… SURREAL_DATABASE=…`
to match Actions, then re-run **Sync corpus to SurrealDB** (`workflow_dispatch`).

`ensure_runtime` applies schema across several fresh connections (default 8,
`ENSURE_RUNTIME_PASSES`) because Surreal Cloud hostnames often resolve to
multiple IPs — a single DEFINE + probe can be green in Actions while the Fly
dyno still misses `artifact` / pref fields. Each pass runs root INFO checks, a
root write probe, and a **record-auth** signup/update/`SELECT artifact` probe.


### Surreal connect timeouts on sign-in

If Fly logs show `auth signin failed … reason=could not connect:
%Mint.TransportError{reason: :timeout}` (or `RPC use timed out during setup`),
the password was never checked — the dyno failed to open / set up the Surreal
WSS session. Common causes:

1. **Surreal Cloud idle pause** (free / low tiers) — wake the instance in the
   Surreal console, wait ~30s, retry sign-in.
2. **Wrong or stale `SURREAL_URL`** on the Fly app (`fly secrets list -a isomer-demo`).
3. **Regional lag** — demo Fly region is `iad`; many Surreal Cloud hosts are
   `aws-usw2`. Latency alone rarely hits 10–15s, but combined with a cold
   instance it can.

The web client retries transient connect failures a few times and keeps an
existing session cookie when LiveView mount times out (so a pause does not
force a logout loop).

## Fly.io

The checked-in demo app is **`isomer-demo`** (`https://isomer-demo.fly.dev`).
The global name `isomer` is already taken on Fly.io.

### Continuous deploy

On every push to `main` (merged PRs), GitHub Actions runs
[`.github/workflows/fly-deploy.yml`](../.github/workflows/fly-deploy.yml) and
deploys with `flyctl deploy -a isomer-demo --remote-only`.

Required Actions secret:

| Secret | How to create |
|---|---|
| `FLY_API_TOKEN` | `fly tokens create deploy -a isomer-demo -x 999999h` → paste into repo **Settings → Secrets and variables → Actions** |

Manual deploy remains available (`workflow_dispatch` on that workflow, or local
`fly deploy`).

### First-time / secrets on the app

```bash
# First time (app already exists for this repo's demo):
#   fly apps create isomer-demo
fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  PHX_HOST=isomer-demo.fly.dev \
  SURREAL_URL=… SURREAL_NAMESPACE=main SURREAL_DATABASE=main
```

`fly.toml` sets `PHX_SERVER=true` and binds internal port `4000`. Health checks
hit `/health` (plain-text liveness; not `/login`). Attach a custom domain with
`fly certs add` when ready.

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

```
mix setup                      # deps + Tailwind/esbuild install + asset build
mix isomer.db.ensure_runtime   # once per Surreal DB
mix phx.server                 # http://localhost:4000
```

UI assets live under `assets/` and compile to `priv/static/assets/` via Tailwind v4 and esbuild (Petal Components). Production images run `mix assets.deploy` in the Dockerfile.
