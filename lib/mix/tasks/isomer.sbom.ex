defmodule Mix.Tasks.Isomer.Sbom do
  @shortdoc "Generate a CycloneDX SBoM (JSON)"
  @moduledoc """
  Writes a CycloneDX Software Bill of Materials for Mix dependencies.

      mix isomer.sbom
      mix sbom

  Default output: `bom.cdx.json` (CycloneDX JSON, schema 1.6).
  Extra flags are forwarded to `mix sbom.cyclonedx` (EEF `sbom` package).

  Examples:

      mix isomer.sbom --pretty
      mix isomer.sbom -o sbom/isomer-1.0.0.cdx.json --pretty
      mix isomer.sbom --only prod
  """

  use Mix.Task

  @default_output "bom.cdx.json"

  @impl Mix.Task
  def run(["--help" | _]), do: Mix.shell().info(@moduledoc)
  def run(["-h" | _]), do: Mix.shell().info(@moduledoc)

  def run(args) do
    forwarded =
      args
      |> ensure_flag(["-f", "--force"], ["--force"])
      |> ensure_output(@default_output)

    Mix.Task.run("sbom.cyclonedx", forwarded)

    output = output_path(forwarded, @default_output)
    Mix.shell().info("CycloneDX SBoM written to #{output}")
  end

  defp ensure_flag(args, markers, insert) do
    if Enum.any?(args, &(&1 in markers)), do: args, else: insert ++ args
  end

  defp ensure_output(args, default) do
    if Enum.any?(args, &(&1 in ["-o", "--output"])) do
      args
    else
      ["-o", default | args]
    end
  end

  defp output_path(args, default) do
    case Enum.find_index(args, &(&1 in ["-o", "--output"])) do
      nil -> default
      i -> Enum.at(args, i + 1) || default
    end
  end
end
