defmodule IsomerWeb.PageController do
  use IsomerWeb, :controller

  alias IsomerWeb.UserAuth

  def home(conn, _params) do
    token = conn.assigns[:surreal_token]

    cond do
      is_binary(token) and token != "" and UserAuth.valid_token?(token) ->
        redirect(conn, to: ~p"/orgs")

      is_binary(token) and token != "" ->
        conn
        |> UserAuth.log_out()
        |> redirect(to: ~p"/login")

      true ->
        redirect(conn, to: ~p"/login")
    end
  end
end
