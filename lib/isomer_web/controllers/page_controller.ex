defmodule IsomerWeb.PageController do
  use IsomerWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:surreal_token] do
      redirect(conn, to: ~p"/orgs")
    else
      redirect(conn, to: ~p"/login")
    end
  end
end
