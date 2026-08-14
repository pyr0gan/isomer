defmodule IsomerWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Adds HTTP Strict Transport Security on HTTPS responses in production.

  Fly already redirects HTTP → HTTPS at the edge (`force_https`). This plug
  does **not** redirect: internal `/health` checks speak HTTP to the dyno and
  must stay 200. HSTS is emitted only when the request is already HTTPS
  (`scheme` or `x-forwarded-proto`).
  """

  @behaviour Plug

  import Plug.Conn

  # One year. No `preload` (hard to undo). `includeSubDomains` is omitted —
  # this app is a single Fly hostname.
  @hsts_value "max-age=31536000"

  def init(opts), do: opts

  def call(conn, opts) do
    enabled? = Keyword.get_lazy(opts, :enabled, &hsts_enabled?/0)

    if enabled? and https_request?(conn) do
      put_resp_header(conn, "strict-transport-security", @hsts_value)
    else
      conn
    end
  end

  def hsts_header_value, do: @hsts_value

  defp hsts_enabled? do
    cfg = Application.get_env(:isomer, IsomerWeb.Endpoint, [])
    Keyword.get(cfg, :hsts, Keyword.get(cfg, :session_cookie_secure, false))
  end

  defp https_request?(conn) do
    conn.scheme == :https or
      conn |> get_req_header("x-forwarded-proto") |> List.first() == "https"
  end
end
