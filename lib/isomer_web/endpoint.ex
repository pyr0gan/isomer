defmodule IsomerWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :isomer

  # `secure` is compile-time: Docker/release builds MIX_ENV=prod so the browser
  # only sends `_isomer_key` over HTTPS. Local HTTP (:dev / :test) must not set
  # Secure or the cookie is dropped. Fly terminates TLS in front of the dyno.
  @session_options [
    store: :cookie,
    key: "_isomer_key",
    signing_salt: "isomer_sess",
    same_site: "Lax",
    http_only: true,
    secure:
      Application.compile_env(
        :isomer,
        [IsomerWeb.Endpoint, :session_cookie_secure],
        Mix.env() == :prod
      )
  ]

  def session_options, do: @session_options

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  plug(Plug.Static,
    at: "/",
    from: :isomer,
    gzip: false,
    only: IsomerWeb.static_paths()
  )

  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(IsomerWeb.Router)
end
