defmodule Mix.Tasks.Isomer.Db.Sync do
  @shortdoc "Sync on-disk corpus into SurrealDB"
  @moduledoc """
      mix isomer.db.sync
      mix isomer.db.sync --dry-run
      mix isomer.db.sync --no-prune
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [dry_run: :boolean, prune: :boolean, help: :boolean],
        aliases: [h: :help]
      )

    if opts[:help] do
      Mix.shell().info(@moduledoc)
      :ok
    else
      Mix.Task.run("app.start")

      dry_run? = Keyword.get(opts, :dry_run, false)
      prune? = Keyword.get(opts, :prune, true)

      try do
        result = Isomer.Db.Sync.sync!(dry_run: dry_run?, prune: prune?)

        summary = %{
          ok: result.ok,
          written: result.written,
          dry_run: result.dry_run,
          prune: result.prune,
          sync_sha: result.sync_sha,
          synced_at: result.synced_at,
          counts: result.counts,
          deleted_counts: Map.new(result.deleted, fn {k, v} -> {k, length(v)} end),
          sync_run: Map.get(result, :sync_run)
        }

        Mix.shell().info("db:sync OK")
        Mix.shell().info(Isomer.JSON.encode!(summary, pretty: true))
      rescue
        e ->
          Mix.shell().error("db:sync FAILED")
          Mix.shell().error(Exception.message(e))

          if System.get_env("DEBUG_SYNC") == "1" do
            Mix.shell().error(Exception.format(:error, e, __STACKTRACE__))
          end

          exit({:shutdown, 1})
      end
    end
  end
end
