import Config

config :isomer, IsomerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_isomer_0123456789abcdef0123456789ab",
  server: false,
  session_cookie_secure: false

config :logger, level: :warning
