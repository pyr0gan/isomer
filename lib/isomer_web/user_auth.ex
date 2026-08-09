defmodule IsomerWeb.UserAuth do
  @moduledoc "Session helpers: Surreal JWT in cookie session + LiveView on_mount."

  import Plug.Conn

  use Phoenix.VerifiedRoutes,
    endpoint: IsomerWeb.Endpoint,
    router: IsomerWeb.Router,
    statics: IsomerWeb.static_paths()

  alias Isomer.Db.Tenant
  alias Isomer.Db.UserClient
  alias Isomer.GuideCopy

  def init(opts), do: opts

  def call(conn, _opts) do
    token = get_session(conn, :surreal_token)
    email = get_session(conn, :surreal_email)

    conn
    |> assign(:surreal_token, token)
    |> assign(:current_email, email)
    |> assign(:current_user, nil)
    |> assign(:guide_prefs, GuideCopy.default_prefs())
  end

  def log_in(conn, token, email) when is_binary(token) and is_binary(email) do
    conn
    |> renew_session()
    |> put_session(:surreal_token, token)
    |> put_session(:surreal_email, email)
  end

  def log_out(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Returns `:ok` if the session JWT still authenticates against Surreal.
  Used to avoid `/login` ↔ `/orgs` redirect loops when the cookie is stale.
  """
  def valid_token?(token) when is_binary(token) and token != "" do
    case UserClient.connect_with_token(token) do
      {:ok, conn} ->
        UserClient.stop(conn)
        true

      {:error, _} ->
        false
    end
  end

  def valid_token?(_), do: false

  def on_mount(:ensure_authenticated, _params, session, socket) do
    case session do
      %{"surreal_token" => token} when is_binary(token) and token != "" ->
        case UserClient.connect_with_token(token) do
          {:ok, conn} ->
            {user, prefs} = load_user_and_prefs(conn)

            socket =
              socket
              |> Phoenix.Component.assign(:surreal, conn)
              |> Phoenix.Component.assign(:surreal_token, token)
              |> Phoenix.Component.assign(
                :current_email,
                (user && user["email"]) || session["surreal_email"]
              )
              |> Phoenix.Component.assign(:current_user, user)
              |> Phoenix.Component.assign(:guide_prefs, prefs)
              |> Phoenix.Component.assign(:nav_org_id, nil)
              |> Phoenix.Component.assign(:nav_assessment_id, nil)
              |> Phoenix.Component.assign(:nav_assessment_title, nil)

            {:cont, socket}

          {:error, _reason} ->
            # Clear the stale cookie via /logout — do not bounce to /login while
            # the invalid token is still in the session (that loops with
            # SessionController.new redirecting authenticated users to /orgs).
            {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/logout")}
        end

      _ ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
    end
  end

  defp load_user_and_prefs(conn) do
    case Tenant.get_current_user(conn) do
      {:ok, user} ->
        {user, GuideCopy.normalize(user)}

      {:error, _} ->
        {nil, GuideCopy.default_prefs()}
    end
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
