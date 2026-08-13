defmodule Isomer.Sbom do
  @moduledoc """
  CycloneDX SBoM helpers for the Mix tooling package.

  Generation still uses the EEF `sbom` Mix task. Change detection ignores
  volatile fields (`serialNumber`, top-level `version`, `metadata.timestamp`)
  so regenerating without dependency changes does not count as an update.
  """

  @default_output "bom.cdx.json"

  @doc "Default on-disk path for a generated CycloneDX JSON file."
  def default_output, do: @default_output

  @doc """
  Generate a CycloneDX JSON file via `mix sbom.cyclonedx`.

  Returns the absolute output path. Extra CLI flags are forwarded.
  """
  def generate!(args \\ []) when is_list(args) do
    forwarded =
      args
      |> ensure_flag(["-f", "--force"], ["--force"])
      |> ensure_output(@default_output)

    Mix.Task.reenable("sbom.cyclonedx")
    Mix.Task.run("sbom.cyclonedx", forwarded)

    output = output_path(forwarded, @default_output)
    Path.expand(output, Isomer.root())
  end

  @doc "Decode CycloneDX JSON from a file path."
  def read_file!(path) when is_binary(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  @doc """
  Canonical form for change detection.

  Drops fields that change on every generation without reflecting dependency
  content: `serialNumber`, BOM `version`, and `metadata.timestamp`.
  """
  def canonicalize(doc) when is_map(doc) do
    doc
    |> Map.drop(["serialNumber", "version"])
    |> Map.update("metadata", %{}, fn
      meta when is_map(meta) -> Map.delete(meta, "timestamp")
      other -> other
    end)
    |> deep_sort()
  end

  @doc "SHA-256 hex digest of the canonical JSON encoding."
  def content_hash(doc) when is_map(doc) do
    doc
    |> canonicalize()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc "Mix app version string from the project."
  def mix_app_version do
    to_string(Mix.Project.config()[:version])
  end

  defp deep_sort(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), deep_sort(v)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Map.new()
  end

  defp deep_sort(list) when is_list(list), do: Enum.map(list, &deep_sort/1)
  defp deep_sort(other), do: other

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
