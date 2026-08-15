defmodule Mix.Tasks.Isomer.Db.SyncSbom do
  @shortdoc "Upsert CycloneDX SBoM into SurrealDB when it changed"
  @moduledoc """
  Publishes the Mix tooling CycloneDX bill of materials to SurrealDB
  (`sbom:isomer_tooling`). Skips the write when the content hash matches the
  stored record (volatile serial/timestamp fields ignored).

      mix isomer.db.sync_sbom
      mix isomer.db.sync_sbom --dry-run
      mix isomer.db.sync_sbom --file bom.cdx.json

  Generates `bom.cdx.json` when `--file` is omitted. Requires Surreal + Vault
  env (same as `mix isomer.db.sync`). Do not run under `MIX_ENV=prod` (Hex
  `sbom` is a `:dev` dependency).
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [dry_run: :boolean, file: :string, help: :boolean],
        aliases: [h: :help, f: :file]
      )

    if opts[:help] do
      Mix.shell().info(@moduledoc)
      :ok
    else
      Isomer.Mix.Boot.start_for_db!()

      try do
        result =
          Isomer.Db.Sbom.sync_if_changed!(
            dry_run: Keyword.get(opts, :dry_run, false),
            path: opts[:file]
          )

        Mix.shell().info("db:sync_sbom OK (#{result.action})")
        Mix.shell().info(Isomer.JSON.encode!(result, pretty: true))
      rescue
        e ->
          Mix.shell().error("db:sync_sbom FAILED")
          Mix.shell().error(Exception.message(e))

          if System.get_env("DEBUG_SYNC") == "1" do
            Mix.shell().error(Exception.format(:error, e, __STACKTRACE__))
          end

          exit({:shutdown, 1})
      end
    end
  end
end
