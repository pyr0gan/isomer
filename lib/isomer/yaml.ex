defmodule Isomer.YAML do
  @moduledoc false

  @doc "Load YAML and normalize dates/times to ISO-8601 strings for schema checks."
  def read!(path) when is_binary(path) do
    path
    |> File.read!()
    |> YamlElixir.read_from_string!()
    |> normalize()
  end

  def normalize(%Date{} = d), do: Date.to_iso8601(d)
  def normalize(%DateTime{} = d), do: DateTime.to_iso8601(d)
  def normalize(%NaiveDateTime{} = d), do: NaiveDateTime.to_iso8601(d)

  def normalize(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), normalize(v)} end)
  end

  def normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  def normalize(other), do: other
end
