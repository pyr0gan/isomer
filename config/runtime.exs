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

evidence_backend =
  case System.get_env("EVIDENCE_BACKEND") do
    "s3" -> Isomer.Evidence.Storage.S3
    "local" -> Isomer.Evidence.Storage.Local
    "memory" -> Isomer.Evidence.Storage.Memory
    _ -> nil
  end

evidence_opts =
  []
  |> then(fn opts ->
    if evidence_backend, do: Keyword.put(opts, :backend, evidence_backend), else: opts
  end)
  |> then(fn opts ->
    case System.get_env("EVIDENCE_LOCAL_ROOT") do
      root when is_binary(root) and root != "" -> Keyword.put(opts, :local_root, root)
      _ -> opts
    end
  end)

if evidence_opts != [] do
  config :isomer, Isomer.Evidence.Storage, evidence_opts
end
