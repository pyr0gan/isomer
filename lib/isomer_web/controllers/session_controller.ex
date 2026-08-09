defmodule IsomerWeb.SessionController do
  use IsomerWeb, :controller

  alias Isomer.Db.UserClient
  alias IsomerWeb.UserAuth

  def new(conn, _params) do
    if conn.assigns[:surreal_token] do
      redirect(conn, to: ~p"/orgs")
    else
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
        render(conn, :new, error: format_error(reason), mode: "signup")
    end
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out()
    |> put_flash(:info, "Signed out")
    |> redirect(to: ~p"/login")
  end

  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(other), do: inspect(other)
end
