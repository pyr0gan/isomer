defmodule IsomerWeb.PageController do
  use IsomerWeb, :controller

  alias IsomerWeb.UserAuth

  def home(conn, _params) do
    token = conn.assigns[:surreal_token]

    cond do
      not (is_binary(token) and token != "") ->
        redirect(conn, to: ~p"/login")

      true ->
        case UserAuth.check_token(token) do
          :valid ->
            redirect(conn, to: ~p"/orgs")

          :unavailable ->
            conn
            |> put_flash(
              :error,
              "Database unreachable right now (timeout). Wait a few seconds and retry."
            )
            |> redirect(to: ~p"/login")

          :invalid ->
            conn
            |> UserAuth.log_out()
            |> redirect(to: ~p"/login")
        end
    end
  end
end
