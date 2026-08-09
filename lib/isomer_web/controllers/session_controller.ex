defmodule IsomerWeb.SessionController do
  use IsomerWeb, :controller

  require Logger

  alias Isomer.Db.UserClient
  alias IsomerWeb.UserAuth

  def new(conn, _params) do
    token = conn.assigns[:surreal_token]

    cond do
      is_binary(token) and token != "" and UserAuth.valid_token?(token) ->
        redirect(conn, to: ~p"/orgs")

      is_binary(token) and token != "" ->
        conn
        |> UserAuth.log_out()
        |> put_flash(:info, "Session expired — sign in again")
        |> render(:new, error: nil, mode: "login")

      true ->
        render(conn, :new, error: nil, mode: "login")
    end
  end

  def create(conn, %{"email" => email, "password" => password}) do
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

  def signup(conn, params) do
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
    |> then(fn
      "The record access signup query failed" ->
        "Could not create account. If you already signed up, use Sign in."

      "The record access signin query failed" ->
        "Invalid email or password."

      # Surreal SIGNIN when email exists but argon2 compare fails (or no row).
      "No record was returned" ->
        "Invalid email or password."

      other ->
        other
    end)
  end

  defp format_error(other), do: inspect(other)
end
