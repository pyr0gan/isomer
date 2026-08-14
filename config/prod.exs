import Config

config :isomer, IsomerWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true,
  # HTTPS-only session cookie (`Set-Cookie: Secure`). Fly already force-redirects
  # HTTP at the edge; this flag stops the browser from attaching `_isomer_key` on
  # any leftover cleartext request.
  session_cookie_secure: true,
  # HSTS on HTTPS responses (Aikido: missing Strict-Transport-Security).
  # Header-only — no Plug.SSL redirect, so Fly HTTP /health stays 200.
  hsts: true

config :logger, level: :info
