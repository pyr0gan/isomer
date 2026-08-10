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
  Checks whether the session JWT still authenticates against Surreal.

  Returns `:valid`, `:invalid`, or `:unavailable` (transient transport/timeout —
  do **not** clear the cookie for `:unavailable`).
  """
  def check_token(token) when is_binary(token) and token != "" do
    case UserClient.connect_with_token(token) do
      {:ok, conn} ->
        UserClient.stop(conn)
        :valid

      {:error, reason} ->
        if UserClient.transient_error?(reason), do: :unavailable, else: :invalid
    end
  end

  def check_token(_), do: :invalid

  @doc "True only when Surreal accepts the JWT (not on transient outages)."
  def valid_token?(token), do: check_token(token) == :valid

  def on_mount(:ensure_authenticated, _params, session, socket) do
    case session do
      %{"surreal_token" => token} when is_binary(token) and token != "" ->
        case UserClient.connect_with_token(token) do
          {:ok, conn} ->
            {user, prefs} = load_user_and_prefs(conn, session)

            socket =
              socket
              |> Phoenix.Component.assign(:surreal, conn)
              |> Phoenix.Component.assign(:surreal_token, token)
              |> Phoenix.Component.assign(
                :current_email,
                (user && user["email"]) || session["surreal_email"]
              )
              |> Phoenix.Component.assign(:current_user, maybe_overlay_name(user, session))
              |> Phoenix.Component.assign(:guide_prefs, prefs)
              |> Phoenix.Component.assign(:nav_org_id, nil)
              |> Phoenix.Component.assign(:nav_assessment_id, nil)
              |> Phoenix.Component.assign(:nav_assessment_title, nil)

            {:cont, socket}

          {:error, reason} ->
            if UserClient.transient_error?(reason) do
              # Keep the cookie — Surreal Cloud free tiers pause; logging out
              # forces a painful re-auth loop while the DB is merely slow.
              {:halt,
               socket
               |> Phoenix.LiveView.put_flash(
                 :error,
                 "Database unreachable right now (timeout). Wait a few seconds and retry."
               )
               |> Phoenix.LiveView.redirect(to: ~p"/login")}
            else
              # Clear the stale cookie via /logout — do not bounce to /login while
              # the invalid token is still in the session (that loops with
              # SessionController.new redirecting authenticated users to /orgs).
              {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/logout")}
            end
        end

      _ ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
    end
  end

  defp load_user_and_prefs(conn, session) do
    case Tenant.get_current_user(conn) do
      {:ok, user} ->
        surreal_prefs = GuideCopy.normalize(user)
        session_prefs = normalize_session_prefs(session["guide_prefs"])
        prefs = GuideCopy.normalize(Map.merge(surreal_prefs, session_prefs))
        {user, prefs}

      {:error, _} ->
        {nil, GuideCopy.normalize(normalize_session_prefs(session["guide_prefs"]))}
    end
  end

  defp normalize_session_prefs(prefs) when is_map(prefs) do
    %{
      "self_role" => prefs["self_role"] || prefs[:self_role],
      "experience_level" => prefs["experience_level"] || prefs[:experience_level],
      "comfort_level" => prefs["comfort_level"] || prefs[:comfort_level]
    }
  end

  defp normalize_session_prefs(_), do: %{}

  defp maybe_overlay_name(nil, _session), do: nil

  defp maybe_overlay_name(user, session) when is_map(user) do
    case session["guide_name"] do
      name when is_binary(name) and name != "" -> Map.put(user, "name", name)
      _ -> user
    end
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
