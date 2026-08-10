defmodule IsomerWeb.Plugs.ForgeryProtection do
  @moduledoc """
  CSRF protection with a friendly recovery path for auth form races.

  Sign-in calls `configure_session(renew: true)`, which rotates the session
  cookie. A second POST (double-click, password-manager retry) can then arrive
  with the **new** cookie and the **old** form `_csrf_token` → Plug would
  normally render a bare "Forbidden" page at `/session` even though the first
  request already established a valid Surreal session.

  In that case we redirect to `/orgs`. Otherwise we send the user back to
  `/login` with a flash instead of a 403.
  """

  import Plug.Conn
  import Phoenix.Controller

  require Logger

  use Phoenix.VerifiedRoutes,
    endpoint: IsomerWeb.Endpoint,
    router: IsomerWeb.Router,
    statics: IsomerWeb.static_paths()

  @auth_paths MapSet.new(["/session", "/session/signup"])

  def init(opts), do: Plug.CSRFProtection.init(opts)

  def call(conn, opts) do
    Plug.CSRFProtection.call(conn, opts)
  rescue
    e in [
      Plug.CSRFProtection.InvalidCSRFTokenError,
      Plug.CSRFProtection.InvalidCrossOriginRequestError
    ] ->
      path = conn.request_path || ""

      if MapSet.member?(@auth_paths, path) and conn.method == "POST" do
        Logger.warning("csrf rejected auth post path=#{path} — recovering instead of 403")

        conn = ensure_flash(conn)

        if present_session_token?(conn) do
          conn
          |> put_flash(:info, "Signed in")
          |> redirect(to: ~p"/orgs")
          |> halt()
        else
          conn
          |> put_flash(:error, "That sign-in form expired. Please try again.")
          |> redirect(to: ~p"/login")
          |> halt()
        end
      else
        reraise e, __STACKTRACE__
      end
  end

  defp ensure_flash(conn) do
    cond do
      Map.has_key?(conn.private, :phoenix_flash) -> conn
      Map.has_key?(conn.private, :phoenix_live_flash) -> conn
      true -> fetch_flash(conn)
    end
  end

  defp present_session_token?(conn) do
    case get_session(conn, :surreal_token) do
      token when is_binary(token) and token != "" -> true
      _ -> false
    end
  end
end
