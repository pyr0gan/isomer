import Config

config :isomer, root: File.cwd!()

config :isomer, IsomerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: IsomerWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: Isomer.PubSub,
  live_view: [signing_salt: "isomer_lv_salt"]

config :phoenix, :json_library, Jason

config :esbuild,
  version: "0.25.4",
  isomer: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "4.1.12",
  isomer: [
    args: ~w(
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :logger, level: :info

import_config "#{config_env()}.exs"
