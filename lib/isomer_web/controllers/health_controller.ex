defmodule IsomerWeb.HealthController do
  @moduledoc "Liveness probe for Fly / load balancers (no auth, no session work)."
  use IsomerWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok\n")
  end
end
