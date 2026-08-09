import Config

# Env vars come from the process environment (CI / host secrets) or a local `.env`
# loaded by `Isomer.Config` when Mix tasks and the web app need Surreal/Vault.

if System.get_env("PHX_SERVER") == "true" do
  config :isomer, IsomerWeb.Endpoint, server: true
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Generate one with: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :isomer, IsomerWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    check_origin: true
end
