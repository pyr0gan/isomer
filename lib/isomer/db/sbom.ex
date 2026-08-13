defmodule Isomer.Db.Sbom do
  @moduledoc """
  Publish the tooling CycloneDX SBoM into SurrealDB.

  Single record `sbom:isomer_tooling`. Upserts only when `content_hash` differs
  from the stored value (volatile BOM fields excluded — see `Isomer.Sbom`).
  """

  alias Isomer.Db.Connect
  alias Isomer.Sbom

  @table "sbom"
  @record_key "isomer_tooling"

  @doc "Surreal record key for the Mix tooling SBoM."
  def record_key, do: @record_key

  @doc "Ensure the `sbom` table exists (root connection)."
  def ensure!(db) do
    {:ok, _} =
      SurrealDB.query(db, """
      DEFINE TABLE IF NOT EXISTS sbom SCHEMALESS
        COMMENT "CycloneDX SBoM for Mix tooling; single current record isomer_tooling";
      """)

    :ok
  end

  @doc """
  Generate (unless `:path` given), compare hash to Surreal, upsert if changed.

  Options:

  - `:dry_run` — compute hash / compare without writing (default false)
  - `:path` — existing CycloneDX JSON file (skips generation)
  - `:generate_args` — forwarded to `Isomer.Sbom.generate!/1` when generating
  - `:sync_sha` — git SHA (defaults to `GITHUB_SHA` / `SYNC_SHA` / `"local"`)
  """
  def sync_if_changed!(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    sync_sha = sync_sha(opts)
    synced_at = DateTime.utc_now() |> DateTime.to_iso8601()

    {path, generated?} =
      case Keyword.get(opts, :path) do
        path when is_binary(path) and path != "" ->
          abs = Isomer.Paths.expand_under!(Isomer.root(), path)
          {abs, false}

        _ ->
          abs = Sbom.generate!(Keyword.get(opts, :generate_args, ["--pretty"]))
          {abs, true}
      end

    doc = Sbom.read_file!(path)
    hash = Sbom.content_hash(doc)
    app_version = Sbom.mix_app_version()

    base = %{
      ok: true,
      dry_run: dry_run?,
      path: path,
      generated: generated?,
      content_hash: hash,
      mix_app_version: app_version,
      sync_sha: sync_sha,
      synced_at: synced_at,
      record: "#{@table}:#{@record_key}"
    }

    if dry_run? do
      Map.merge(base, %{action: :dry_run, written: false})
    else
      db = Connect.connect!()

      try do
        ensure!(db)

        case stored_hash(db) do
          {:ok, ^hash} ->
            Map.merge(base, %{action: :unchanged, written: false})

          {:ok, previous} ->
            write!(db, doc, hash, app_version, sync_sha, synced_at)

            Map.merge(base, %{
              action: :updated,
              written: true,
              previous_content_hash: previous
            })

          :missing ->
            write!(db, doc, hash, app_version, sync_sha, synced_at)
            Map.merge(base, %{action: :created, written: true})
        end
      after
        SurrealDB.close(db)
      end
    end
  end

  defp stored_hash(db) do
    case SurrealDB.query(
           db,
           """
           SELECT content_hash FROM ONLY type::record($table, $key);
           """,
           %{"table" => @table, "key" => @record_key}
         ) do
      {:ok, results} ->
        case unwrap_one(results) do
          {:ok, %{"content_hash" => hash}} when is_binary(hash) and hash != "" ->
            {:ok, hash}

          {:ok, _} ->
            :missing

          :missing ->
            :missing
        end

      {:error, _} ->
        :missing
    end
  end

  defp write!(db, doc, hash, app_version, sync_sha, synced_at) do
    content = %{
      "kind" => "cyclonedx",
      "format" => "json",
      "spec_version" => doc["specVersion"],
      "content_hash" => hash,
      "document" => doc,
      "mix_app_version" => app_version,
      "component_count" => length(doc["components"] || []),
      "sync_sha" => sync_sha,
      "synced_at" => synced_at,
      "generated_at" => get_in(doc, ["metadata", "timestamp"]),
      "content_source" => "ci"
    }

    rid = SurrealDB.RecordId.new(@table, @record_key)

    case SurrealDB.upsert(db, rid, content) do
      {:ok, _} -> :ok
      {:error, err} -> raise "upsert sbom:#{@record_key} failed: #{inspect(err)}"
    end
  end

  defp sync_sha(opts) do
    Keyword.get(opts, :sync_sha) ||
      System.get_env("GITHUB_SHA") ||
      System.get_env("SYNC_SHA") ||
      "local"
  end

  defp unwrap_one(results) when is_list(results) do
    results
    |> List.flatten()
    |> Enum.find_value(:missing, fn
      row when is_map(row) and not is_struct(row) -> {:ok, row}
      [row | _] when is_map(row) and not is_struct(row) -> {:ok, row}
      _ -> nil
    end)
    |> case do
      {:ok, _} = ok -> ok
      nil -> :missing
      :missing -> :missing
    end
  end

  defp unwrap_one(_), do: :missing
end
