defmodule Isomer.Db.IngestSample do
  @moduledoc "Hello-world ingest: upsert one corpus requirement and read it back."

  alias Isomer.Db.{Connect, Params}
  alias Isomer.YAML

  @default_path "frameworks/annex-sl-core/1.0/requirements/4.1-context.yaml"

  def run!(path \\ @default_path) do
    abs = Path.expand(path, Isomer.root())
    doc = YAML.read!(abs)

    unless is_binary(doc["id"]) and doc["id"] != "" do
      raise ArgumentError, "YAML at #{path} is missing required field id"
    end

    key = doc["id"]
    db = Connect.connect!()

    try do
      fields = Map.drop(doc, ["id"])

      content =
        fields
        |> Map.put("corpus_id", key)
        |> Map.put("content_source", Params.content_source())
        |> Map.put("source_path", path)
        |> Map.put("ingested_at", DateTime.utc_now() |> DateTime.to_iso8601())

      rid = SurrealDB.RecordId.new("requirement", key)

      {:ok, written} = SurrealDB.upsert(db, rid, content)

      {:ok, selected} =
        SurrealDB.query(
          db,
          ~s|SELECT id, title, framework, ref, source_path, domains FROM type::record("requirement", $key);|,
          %{"key" => key}
        )

      %{key: key, written: written, selected: selected}
    after
      SurrealDB.close(db)
    end
  end
end
