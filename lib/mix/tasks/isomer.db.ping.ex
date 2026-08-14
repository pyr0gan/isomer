defmodule Mix.Tasks.Isomer.Db.Ping do
  @shortdoc "Probe SurrealDB connectivity (password from Vault)"
  @moduledoc "Connect via WSS using Vault-backed credentials and run RETURN 'isomer-ok'."

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Isomer.Mix.Boot.start_for_db!()

    try do
      result = Isomer.Db.Connect.ping!()
      Mix.shell().info("db:ping OK")
      Mix.shell().info(Isomer.JSON.encode!(result, pretty: true))
    rescue
      e ->
        Mix.shell().error("db:ping FAILED")
        Mix.shell().error(Exception.message(e))
        exit({:shutdown, 1})
    end
  end
end
