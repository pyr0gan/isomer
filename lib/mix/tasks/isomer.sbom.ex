defmodule Mix.Tasks.Isomer.Sbom do
  @shortdoc "Generate a CycloneDX SBoM (JSON)"
  @moduledoc """
  Writes a CycloneDX Software Bill of Materials for Mix dependencies.

      mix isomer.sbom
      mix sbom

  Default output: `bom.cdx.json` (CycloneDX JSON, schema 1.6).
  Extra flags are forwarded to `mix sbom.cyclonedx` (EEF `sbom` package).

  To publish into SurrealDB (upsert only when dependencies changed):

      mix isomer.db.sync_sbom

  Examples:

      mix isomer.sbom --pretty
      mix isomer.sbom -o sbom/isomer.cdx.json --pretty
      mix isomer.sbom --only prod
  """

  use Mix.Task

  @impl Mix.Task
  def run(["--help" | _]), do: Mix.shell().info(@moduledoc)
  def run(["-h" | _]), do: Mix.shell().info(@moduledoc)

  def run(args) do
    output = Isomer.Sbom.generate!(args)
    Mix.shell().info("CycloneDX SBoM written to #{output}")
  end
end
