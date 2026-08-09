defmodule Isomer.Schema do
  @moduledoc """
  JSON Schema helpers.

  Corpus schemas declare draft 2020-12; `ex_json_schema` validates drafts 4/6/7.
  We rewrite `$schema` to draft-07 for resolution — our shapes only use features
  common to both (type/required/enum/properties/pattern/format/additionalProperties).
  """

  @draft7 "http://json-schema.org/draft-07/schema#"

  def load!(name) do
    path = Path.join([Isomer.root(), "schemas", name])

    path
    |> File.read!()
    |> Jason.decode!()
    |> Map.put("$schema", @draft7)
    |> ExJsonSchema.Schema.resolve()
  end

  def validate(resolved, doc) when is_map(doc) do
    case ExJsonSchema.Validator.validate(resolved, doc) do
      :ok -> []
      {:error, errors} -> Enum.map(errors, &format_error/1)
    end
  end

  defp format_error({msg, path}) when is_binary(msg) do
    loc = path_to_json_path(path)
    "#{loc}: #{msg}"
  end

  defp format_error(other), do: inspect(other)

  defp path_to_json_path([]), do: "$"
  defp path_to_json_path(path), do: "$." <> Enum.join(path, ".")
end
