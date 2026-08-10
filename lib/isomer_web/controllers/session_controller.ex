defmodule IsomerWeb.SessionController do
  use IsomerWeb, :controller

  require Logger

  alias Isomer.Db.UserClient
  alias IsomerWeb.UserAuth

  def new(conn, _params) do
    conn = prevent_auth_caching(conn)
    token = conn.assigns[:surreal_token]

    cond do
      not (is_binary(token) and token != "") ->
        render(conn, :new, error: nil, mode: "login")

      true ->
        case UserAuth.check_token(token) do
          :valid ->
            redirect(conn, to: ~p"/orgs")

          :unavailable ->
            conn
            |> put_flash(
              :error,
              "Database unreachable right now (timeout). Wait a few seconds and retry — your session was kept."
            )
            |> render(:new, error: nil, mode: "login")

          :invalid ->
            conn
            |> UserAuth.log_out()
            |> put_flash(:info, "Session expired — sign in again")
            |> render(:new, error: nil, mode: "login")
        end
    end
  end

  def create(conn, %{"email" => email, "password" => password}) do
    conn = prevent_auth_caching(conn)

    # Idempotent: a racing POST after a successful renew may still reach here
    # with a valid session if CSRF happened to match.
    if already_signed_in?(conn) do
      conn
      |> put_flash(:info, "Signed in")
      |> redirect(to: ~p"/orgs")
    else
      case UserClient.signin!(email, password) do
        {:ok, %{token: token, email: email, conn: db}} ->
          UserClient.stop(db)

          conn
          |> UserAuth.log_in(token, email)
          |> put_flash(:info, "Signed in")
          |> redirect(to: ~p"/orgs")

        {:error, reason} ->
          log_auth_failure("signin", email, reason)
          render(conn, :new, error: format_error(reason), mode: "login")
      end
    end
  end

  def signup(conn, params) do
    conn = prevent_auth_caching(conn)

    if already_signed_in?(conn) do
      conn
      |> put_flash(:info, "Signed in")
      |> redirect(to: ~p"/orgs")
    else
      attrs = %{
        "email" => params["email"],
        "password" => params["password"],
        "name" => params["name"] || params["email"]
      }

      case UserClient.signup!(attrs) do
        {:ok, %{token: token, email: email, conn: db}} ->
          UserClient.stop(db)

          conn
          |> UserAuth.log_in(token, email)
          |> put_flash(:info, "Account created")
          |> redirect(to: ~p"/orgs")

        {:error, reason} ->
          log_auth_failure("signup", attrs["email"], reason)
          render(conn, :new, error: format_error(reason), mode: "signup")
      end
    end
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out()
    |> put_flash(:info, "Signed out")
    |> redirect(to: ~p"/login")
  end

  defp log_auth_failure(kind, email, reason) do
    Logger.warning("auth #{kind} failed email=#{inspect(email)} reason=#{format_error(reason)}")
  end

  # Surreal masks most SIGNUP failures as a generic string (by design). Our ACCESS
  # SIGNUP uses THROW for common cases; strip the "An error occurred: " prefix.
  defp format_error(%{message: msg}) when is_binary(msg) do
    msg
    |> String.replace_prefix("An error occurred: ", "")
    |> then(&humanize_auth_message/1)
  end

  defp format_error(%Mint.TransportError{reason: :timeout}) do
    db_unreachable_message()
  end

  defp format_error(other) do
    if UserClient.transient_error?(other) do
      db_unreachable_message()
    else
      inspect(other)
    end
  end

  defp humanize_auth_message(msg) do
    cond do
      msg == "The record access signup query failed" ->
        "Could not create account. If you already signed up, use Sign in."

      msg == "The record access signin query failed" ->
        "Invalid email or password."

      # Surreal SIGNIN when email exists but argon2 compare fails (or no row).
      msg == "No record was returned" ->
        "Invalid email or password."

      UserClient.transient_error?(%{message: msg}) ->
        db_unreachable_message()

      true ->
        msg
    end
  end

  defp db_unreachable_message do
    "Could not reach the database (timeout). SurrealDB may be waking from idle — wait a few seconds and try again."
  end

  defp already_signed_in?(conn) do
    case conn.assigns[:surreal_token] do
      token when is_binary(token) and token != "" ->
        UserAuth.check_token(token) == :valid

      _ ->
        false
    end
  end

  # Login HTML embeds a session-bound CSRF token; caching it across sessions
  # produces exactly the /session → Forbidden race users hit after sign-in.
  defp prevent_auth_caching(conn) do
    conn
    |> put_resp_header("cache-control", "no-store, no-cache, must-revalidate, max-age=0")
    |> put_resp_header("pragma", "no-cache")
  end
end
