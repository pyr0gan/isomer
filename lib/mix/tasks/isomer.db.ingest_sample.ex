defmodule Mix.Tasks.Isomer.Db.IngestSample do
  @shortdoc "Upsert one sample requirement into SurrealDB"
  @moduledoc """
      mix isomer.db.ingest_sample
      mix isomer.db.ingest_sample frameworks/annex-sl-core/1.0/requirements/4.1-context.yaml
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Isomer.Mix.Boot.start_for_db!()
    path = List.first(args)

    try do
      result =
        if path do
          Isomer.Db.IngestSample.run!(path)
        else
          Isomer.Db.IngestSample.run!()
        end

      Mix.shell().info("ingest-sample OK")
      Mix.shell().info(Isomer.JSON.encode!(result, pretty: true))
    rescue
      e ->
        Mix.shell().error("ingest-sample FAILED")
        Mix.shell().error(Exception.message(e))
        exit({:shutdown, 1})
    end
  end
end
