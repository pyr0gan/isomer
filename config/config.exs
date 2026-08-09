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

config :logger, level: :info

import_config "#{config_env()}.exs"
