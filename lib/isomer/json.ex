defmodule Isomer.JSON do
  @moduledoc "JSON helpers that stringify SurrealDB typed values for CLI output."

  def encode!(term, opts \\ []) do
    term
    |> sanitize()
    |> Jason.encode!(opts)
  end

  def sanitize(%SurrealDB.RecordId{} = rid), do: SurrealDB.RecordId.to_string(rid)
  def sanitize(%SurrealDB.Table{name: name}), do: name
  def sanitize(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def sanitize(%Date{} = d), do: Date.to_iso8601(d)
  def sanitize(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)

  def sanitize(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {sanitize_key(k), sanitize(v)} end)
  end

  def sanitize(list) when is_list(list), do: Enum.map(list, &sanitize/1)
  def sanitize(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> sanitize()
  def sanitize(other), do: other

  defp sanitize_key(k) when is_atom(k), do: Atom.to_string(k)
  defp sanitize_key(k), do: k
end
