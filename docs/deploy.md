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
| `SECRET_KEY_BASE` | Cookie / LiveView signing |
| `PHX_HOST` | Public hostname (no scheme) |
| `PORT` | HTTP listen port (platform usually sets this) |
| `PHX_SERVER` | `true` so the endpoint accepts connections |
| `SURREAL_URL` | `wss://…/rpc` |
| `SURREAL_NAMESPACE` / `SURREAL_DATABASE` | Same as sync |
| `VAULT_*` | Only needed if you run Mix tasks in the same image |

Signup/signin use Surreal record access and do **not** need the Vault password
on the web process. Keep Vault on a one-off release command or CI for schema
sync.

## Fly.io

```bash
fly launch --no-deploy   # use the checked-in Dockerfile / fly.toml
fly secrets set SECRET_KEY_BASE=… PHX_HOST=your-app.fly.dev \
  SURREAL_URL=… SURREAL_NAMESPACE=main SURREAL_DATABASE=main
fly deploy
```

`fly.toml` sets `PHX_SERVER=true` and binds `PORT`. Attach a custom domain with
`fly certs add` when ready.

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
