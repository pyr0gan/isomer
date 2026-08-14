import Config

config :isomer, IsomerWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  session_cookie_secure: false,
  hsts: false,
  secret_key_base: "dev_only_secret_key_base_isomer_replace_in_prod_0123456789abcdef",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:isomer, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:isomer, ~w(--watch)]}
  ]

config :isomer, IsomerWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"lib/isomer_web/(controllers|live|components)/.*(ex|heex)$",
      ~r"lib/isomer_web/controllers/.*/.*(heex)$",
      ~r"assets/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$"
    ]
  ]

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
